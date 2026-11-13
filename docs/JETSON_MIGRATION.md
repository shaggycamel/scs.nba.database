# Jetson Postgres migration

Working notes and plan for moving the analytics database from CockroachDB Cloud
to a single PostgreSQL instance on the Jetson. The customer-facing slice stays on
Cockroach.

Status: **planning**. No production cutover has happened.

## Target shape

| Stays on CockroachDB                            | Moves to Jetson Postgres |
| ----------------------------------------------- | ------------------------ |
| `fty.customer`                                  | everything else in `nba`, `statyx`, `fty`, `util` |
| `fty.customer_league`                           | all of `mod` |
| `fty.league`                                    | |
| `fty.league_competitor`                         | |
| `util.draft_player_log`                         | |
| their four `_vw` views (`customer_vw`, `customer_league_vw`, `league_vw`, `league_competitor_vw`) | |

`util.update_log` and `util.update_schedule` move with analytics. That keeps
`nba/database` on a single connection (`hub.db`) and makes the NUC the only
cross-host writer. It also means a Jetson outage stops the schedule, not just
the writes — accepted.

Everything customer-facing is a build-time read:

- `entry` authenticates against `fty.customer_vw` on Cockroach.
- `league` data is baked at build time (`deploy/cron.sh` -> `_generate_base.R`).
- `draft` bakes its player pool; the only runtime table it touches is
  `util.draft_player_log`.

So Hugging Face never needs a route to the Jetson. That is the main reason for
this split.

## Findings from the 2026-11-13 scan

Mac Postgres vs CockroachDB, catalog plus targeted aggregates.

### Freshness

- Mac is frozen at **2026-11-03** (last `update_log` row, last played game
  `2026-11-01`, last injury `2026-11-02`).
- Cockroach is live: `scs.nba.database` last wrote **2026-11-13 07:02**,
  dashboard build **05:03**, model runner **05:46**.
- Delta window: **2026-11-02 .. 2026-11-12**, 164 games.

### Objects

- 89 objects match by name.
- Mac only: `nba.schedule_vw` — not in `sql/views/`, no references. Dropped from
  the Mac on 2026-11-13.
- Cockroach only: 12 `mod.*` objects and `util.sql_grant`.

### Columns

- `nba.team_roster.stint_id` is Mac-only, unregistered in
  `util.table_column_order`, unused in code. Do not carry it.
- Other "missing" columns are Cockroach's implicit `rowid`. It is listed in
  `information_schema` but not returned by `SELECT *`, so a row copy is clean.
- Type drift: `integer` on the Mac where Cockroach has `bigint` (player keys,
  review ids, schedule sequence columns). Use `bigint` on the Jetson.
  `text` vs `character varying` is cosmetic.

### Indexes

Cockroach's index list is mostly the implicit `rowid` primary key. The only real
ones are the `mod.*` keys (including `player_archetype_player_date_idx` and
`player_archetype_season_idx`) and `util.sql_grant_pkey`.

The Mac actually has four indexes Cockroach lacks: `fty.customer_league
(customer_id, season, platform, league_id)`, `fty.customer_platform
(customer_id, platform)`, `fty.league_categories (season, platform, league_id,
category)`, and `nba.team_roster (stint_id)`.

Cockroach's set is not worth copying. The Jetson keys are designed fresh in
`sql/indexes/postgres.sql`.

### Data deltas (Mac -> Cockroach)

| Table                             | Mac     | Cockroach | Delta |
| --------------------------------- | ------- | --------- | ----- |
| `nba.player_box_score` (Nov 2+)   | 0       | 4,322     | 4,322 |
| `nba.team_box_score` (Nov 2+)     | 0       | 328       | 328   |
| `nba.play_by_play` (Nov 2+)       | 0       | 84,290    | 84,290 |
| `nba.injuries`                    | 63,767  | 64,497    | 730   |
| `nba.team_roster`                 | 10,911  | 10,952    | 41    |
| `nba.league_game_schedule`        | 48,932  | 48,932    | winners only |
| `fty.competitor_roster`           | 159,099 | 165,954   | 6,855 |
| `fty.matchup_box_score`           | 18,834  | 19,960    | 1,126 |
| `fty.matchup_result`              | 1,688   | 1,736     | 48    |
| `util.player_source_id`           | 5,335   | 5,338     | 3     |
| `util.update_schedule`            | 23      | 25        | 2     |
| `mod.*`                           | 0       | 12,297    | all   |

Identical: `util.player`, `util.table_column_order`, `util.draft_player_log`,
`nba.transaction_log`, `nba.player_info`, `nba.player_season_stats`,
`fty.customer_league`, `fty.league`, `fty.league_competitor`, and the three real
customer password hashes.

### Authority exception

**`util.player_identity_review`: 78 rows on the Mac, 0 on Cockroach.**

All 78 rows are `status = 'applied'` (5–6 October 2026), so this is an audit log
of corrections already reflected in `util.player` and `util.player_source_id` —
not state. Cockroach does not need it. Carry the rows in the Jetson seed so the
history survives; the reviewer writes to whichever database `[runtime]` points
at, so the Jetson is their new home.

Other local-only drift, do not propagate:

- `fty.customer.__test_customer__` (a test row).
- `nba.team_roster.stint_id`.
- `nba.schedule_vw` (already dropped).

`fty.free_agents` has 63 more distinct snapshot timestamps on the Mac but fewer
rows; Cockroach has the newer snapshots. Not worth reconciling.

## Decisions

- **Engine/version:** PostgreSQL 15 or newer (Mac is 15.1; dump/restore works
  upward, not down).
- **Hosting:** Docker on the Jetson, pinned image, `restart: unless-stopped`.
  Docker 29.1.3 is already there.
- **Network:** LAN (`192.168.68.0/24`) and Tailscale only. No public port. HF has
  no route by design.
- **Roles:** owner/writer for the NUC and model runner; `kobe_public` with
  `SELECT` on views for read clients. Apply `util.sql_grant` after views.
- **Time:** server and session `UTC`.
- **Backups:** nightly `pg_dump -Fc` on the Jetson, copied to the NUC, then
  encrypted and pushed to the existing MEGA account with `rclone`. Details in
  [Backups](#backups).
- **Storage:** eMMC, ~27 GB free. Data is ~1.5 GB; budget ~3 GB with bloat and
  tune autovacuum for the delete-then-append write pattern.

## Making the Mac congruent

Two options. Chosen: rebuild into a fresh database, not patch in place.

1. `createdb nba_seed`; leave `nba` untouched as rollback.
2. Copy every base table from Cockroach (`nba`, `statyx`, `fty`, `util`, `mod`);
   exclude `anl` and `scratch`. Cockroach is the source, so no skip list applies.
3. Carry `util.player_identity_review` in the Jetson seed. It is an applied
   audit log, not state; Cockroach does not need it, and rebuilding the Mac from
   Cockroach will drop it.
4. Apply views from the repo: `apply_views.py --db-con postgres-seed`. It already
   guards on `kobe_public` not existing locally.
5. Apply `sql/indexes/postgres.sql`. It first drops whatever keys the dump
   brought across, then adds the fresh design. Never run it against Cockroach.
6. Verify counts and watermarks against Cockroach, then `pg_dump -Fc
   --no-owner --no-privileges nba_seed`.

The Jetson gets that dump. This carries types, keys and indexes in one pass and
avoids a Polars rewrite.

The Mac seed needs `util.sql_grant`; it does not exist there. Take it from
Cockroach or apply `sql/tables/util.sql_grant.sql`.

## Cutover

1. Pause `util.update_schedule` rows.
2. Final delta: copy the Nov 2+ window and `mod` into the Jetson (or seed from
   the refreshed Mac dump).
3. Apply `sql/indexes/postgres.sql` and `ANALYZE`.
4. `apply_views.py --db-con jetson-write`, then `apply_sql_grant`.
5. Flip selectors:
   - NUC `DB_CON=jetson-write`
   - `mod/_runner` `SCS_MOD_DB_SECTION=jetson-write`
   - dashboard build `NBA_DB_SECTION=jetson-read`
   - draft build `NBA_DB_SOURCE=jetson-read`; runtime stays Cockroach
   - entry unchanged (`cockroach-read`)
6. Run one full cycle, compare counts, unpause.
7. Add the publish step: `fty.league`, `fty.league_competitor` and
   `fty.customer_league` from the Jetson to Cockroach after the `fty` jobs, so
   entry sees the current registry.

Keep the Cockroach analytics tables for a rollback window before dropping them.

## Backups

Three copies in three failure domains.

| Layer | Where | Frequency | Retention | Protects against |
| --- | --- | --- | --- | --- |
| Jetson | `/srv/backups` | nightly | 7 | bad migration, accidental delete |
| NUC | `/srv/nba-backups` | nightly rsync | 14 daily + 8 weekly | Jetson disk failure |
| MEGA | `nba-backups/` | daily | 30 daily + 12 monthly | site loss (fire, theft) |

### Jetson

Run the dump from inside the container so the binary matches the server:

```bash
docker exec nba-pg pg_dump -U scs -Fc -Z6 nba > /srv/backups/nba-$(date -u +%F).dump
```

`pg_dump` takes a consistent snapshot, so writes can continue. Keep 7 days —
this is the same disk, so it is for fast restores, not disaster recovery.

### NUC

`rsync` the newest dump after the Jetson run, keep 14 daily and 8 weekly, then
push to MEGA from here. The NUC uploads rather than the Jetson so a Jetson
outage cannot also stop the off-site copy.

### MEGA

- `rclone` remote `mega:`, directory `nba-backups/`.
- The account has 750 GB, so retention is storage-cheap: 30 daily plus 12
  monthly is roughly 17 GB at ~400 MB a dump.
- Encrypt before upload, since a dump is a complete copy of the database:

  ```bash
  age -r "$(cat ~/.config/scs_backup_age.pub)" \
      -o nba-$(date -u +%F).dump.age /srv/nba-backups/nba-$(date -u +%F).dump
  ```

- Dated filenames are the only versioning MEGA provides. Never prune to one
  copy, and do not enable a retention rule that could delete the newest file.
- Private key at `~/.config/scs_backup_age.key` (mode 600), with a copy in the
  password manager. Losing it loses every backup.
- `rclone` config at `~/.config/rclone/rclone.conf` (mode 600). If MEGA has 2FA
  enabled, rclone needs the code once at setup, then stores a session.
- MEGA has a monthly transfer quota and no object lock. Uploads are ~400 MB a
  week; restores count against the same quota, so keep the account recoverable.

### Restore drill

Monthly, on the NUC:

1. `rclone copy mega:nba-backups/nba-YYYY-MM-DD.dump.age .`
2. `age -d -i ~/.config/scs_backup_age.key < ...age > ...dump`
3. `createdb nba_restore_test`
4. `pg_restore -d nba_restore_test --no-owner --no-privileges ...dump`
5. Count checks against `nba.player_box_score`, `util.update_log` and `mod.*`,
   then `dropdb nba_restore_test`.

A backup that has never been restored is a hypothesis.

### Monitoring

Alert through the existing failure-email path in `__main__.py` (`[smtp]`:
`SMTP_USER`, `SMTP_PASSWORD`, `ALERT_TO`) when the newest dump on the NUC is
older than 36 hours, or the newest MEGA object is older than the chosen cadence.
Run the check from the NUC: if the Jetson is down, the check still fires.

### RPO / RTO

- RPO 24 hours. Most tables rebuild from the NBA/Statyx/ESPN APIs; the
  irreplaceable parts are `util.update_log`, the `mod.*` outputs and the
  identity-review history.
- RTO about an hour: restore ~1.5 GB, apply views and keys, grant.
- `fty.customer` and `util.draft_player_log` stay on Cockroach and remain covered
  by its managed backups, so they are not in these dumps.

## Open items

- **Paired change required in `scs_hub`.** Cockroach carries the same 10
  duplicate `statyx.schedule` rows as the Mac. `StatyxPipeline.get_schedule`
  (`src/scs_hub/statyx.py:63`) replaces the season and writes the API frame
  unchanged, and its own comment notes the source repeats game ids. With the new
  primary key, the next rewrite will fail unless that function dedupes the frame
  (`.unique()`) before `write_ordered`. Land that change before pointing
  ingestion at the Jetson.
- `statyx.usage_shock` and `util.update_log` are intentionally unkeyed; confirm
  no consumer needs a stable row id.
- `nba/mod/pts` is legacy and unmaintained; do not carry `anl.*` or its
  `check_update_log.sql`.
- Decide whether `util.deps_saved_ddl` is needed at all.
