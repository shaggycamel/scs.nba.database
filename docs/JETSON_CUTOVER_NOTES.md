# Jetson cutover notes

Last updated: 2026-11-14 18:30 NZDT (05:30 UTC).

Status: **cut over**. Analytics reads and writes are on the Jetson. Cockroach
remains authoritative for customer data.

This is the handover/ops record. The design and decision history is in
[JETSON_MIGRATION.md](JETSON_MIGRATION.md).

## What is live

- `nba`, `statyx`, `fty`, `util` and `mod` live in PostgreSQL 17 on the Jetson
  (`scs-nba-pg`, database `nba`).
- The NUC runs database, model and dashboard jobs against the Jetson.
- Cockroach still owns `fty.customer`, `fty.customer_league`,
  `util.draft_player_log` and the entry app.
- `fty.league` and `fty.league_competitor` are written on the Jetson and
  published back to Cockroach for the entry app.
- Backups run from the Jetson to the NUC, then encrypted to MEGA.

## Timeline

### Seed and local build

- Created `nba_seed` on the Mac as a full copy of Cockroach.
- Synced `fty`, `statyx`, `mod`, `util` and `nba`; top-up-only for
  `nba.player_box_score` and `nba.play_by_play`.
- Preserved the 78 `util.player_identity_review` rows.
- Applied the `bigint` key types, dropped `nba.team_roster.stint_id`, added
  `util.sql_grant`, applied all views and `sql/indexes/postgres.sql`.
- The index pass removed 10 exact duplicate `statyx.schedule` rows
  (6,489 → 6,479).
- Dumped `nba_seed` and restored it into the Jetson `nba` database.
- Reapplied 37 views, applied `util.sql_grant`, and ran `ANALYZE`.

### Backups

- Added `deploy/backups/`:
  - `jetson_dump.sh` (Jetson, 7 daily)
  - `nuc_backup.sh` (NUC, 14 daily + 8 weekly, age encryption, MEGA upload)
  - `check_backups.py` (NUC, 36-hour freshness alert)
  - `restore_drill.sh` (NUC, throwaway PostgreSQL 17 container)
- Installed `age`; installed official rclone 1.76 in `~/.local/bin` because
  Ubuntu's rclone lacks the MEGA backend.
- Generated `~/.config/scs_backup_age.key` on the NUC; public key in
  `scs_backup_age.pub`.
- Configured the `mega` rclone remote.
- First dump, NUC copy, encrypted MEGA upload and full restore drill all
  passed.
- Cron installed on both hosts. First post-cutover backup is due at 03:15 NZDT.

### Cutover

- Paused all 25 `util.update_schedule` rows on Cockroach.
- Ran `scripts/final_delta.py --target-section jetson-write`.
- Flipped the NUC cron:
  - database: `DB_CON=jetson-write`
  - model runner: `SCS_MOD_DB_SECTION=jetson-write`
  - dashboard: `NBA_DB_SECTION=jetson-read`,
    `NBA_UPDATE_LOG_SECTION=jetson-write`
- Added the Monday registry publish cron.
- Unpaused the Jetson schedule.
- Ran daily, weekly and intraday database cycles plus model daily and weekly
  against production. All new `util.update_log` rows succeeded.
- Published `fty.league` and `fty.league_competitor` back to Cockroach.
- Read the Jetson views as `kobe_public` from the NUC.

## Fixes made during the migration

- `nba.play_by_play_vw` joined the two-row schedule table and doubled every
  play. Fixed to join one row per game (`4687aa2`).
- `StatyxComponent.get_schedule` wrote the source frame unchanged; the new
  `statyx.schedule` key needed exact duplicates removed. Fixed with `.unique()`
  in `scs_hub 41e24f3`, pinned in `nba/database c8ea486`.
- Restore drill raced the PostgreSQL entrypoint before `POSTGRES_DB` existed.
  Fixed to wait for the database itself (`fef6df6`).
- Ubuntu's rclone had no MEGA backend. Switched to the official binary in
  `~/.local/bin` (`66e039d`).
- The model runner did not pass the database section to remote jobs. Fixed in
  `nba/mod/_runner` (`cfdf266`, `4ec285c`).
- `player_archetypes` passed `--db-con` only to its logger, not its pipeline or
  publisher. Fixed in `nba/mod/player_archetypes` (`347b687`).
- Game 22500711 (OKC @ DEN, 2026-02-01) was missing from `player_box_score` in
  both databases. Fetched 24 rows from the NBA API and wrote them to both.

## Current data counts (Jetson)

| Table | Rows |
| --- | ---: |
| `nba.player_box_score` | 597,038 |
| `nba.play_by_play` | 4,143,371 |
| `nba.injuries` | 64,525 |
| `statyx.schedule` | 6,479 |
| `util.update_log` | 15,033 |
| `mod.injury_daily_forecast_base` | 2,072 |
| `mod.player_archetype_base` | 3,039 |
| `mod.team_hierarchy_base` | 7,557 |

Cockroach's `mod` tables contain the pre-fix/errant model runs and are not the
authority: `injury_daily_forecast_base` 2,077, `player_archetype_base` 2,971,
`team_hierarchy_base` 7,555. `statyx.schedule` is 6,489 there by design (the ten
duplicates remain in Cockroach).

## Selectors and schedule

NUC crontab:

- Database jobs: `DB_CON=jetson-write`
- Model runner: `SCS_MOD_DB_SECTION=jetson-write`
- Dashboard: `NBA_DB_SECTION=jetson-read`,
  `NBA_UPDATE_LOG_SECTION=jetson-write`
- Registry publish: Monday 12:30 UTC

Cockroach `util.update_schedule` remains paused (25/25). The Jetson schedule is
unpaused (0/25).

Branch state:

- `nba/database`: NUC and Jetson are on `jetson-postgres-migration`.
- `nba/mod/_runner`: `main` (`4ec285c`).
- `nba/mod/player_archetypes`: `main` (`347b687`).
- `scs_hub`: `main` (`41e24f3`).

## What happens next (NZDT)

Tonight:

- 20:00 — first database intraday with `DB_CON=jetson-write`
- 21:05 — first dashboard build with `NBA_DB_SECTION=jetson-read`

Overnight:

- 02:00 — daily database run
- 03:15 — Jetson backup dump
- 03:45 — NUC sync and MEGA upload
- 04:15 — backup freshness check
- 05:00 — intraday database run
- 05:30 — dashboard daily, full `jetson-read` base regeneration

Review at 08:00–09:00 NZDT:

- `util.update_log` on the Jetson: no failures after the cutover
- `~/shaggy_camel_sports/nba/database/cron.log` on the NUC
- `~/shaggy_camel_sports/nba/fty/league_dash/cron.log` on the NUC
- `~/shaggy_camel_sports/nba/database/backup.log` and the MEGA daily listing
- `util.update_schedule` still unpaused on the Jetson

Then:

- Set `NBA_DB_SOURCE=jetson-read` for the next draft build.
- Merge `jetson-postgres-migration` to `main` and switch NUC/Jetson checkouts
  back to `main`.
- Keep Cockroach analytics tables for the rollback window; drop them after a
  clean period.
- Open items: Mac LAN access, `statyx.usage_shock` / `util.update_log` stable
  id decision, `util.deps_saved_ddl`, legacy `pts`.

## Rollback

1. Unpause the 25 `util.update_schedule` rows on Cockroach.
2. Revert the NUC selectors to `DB_CON=cockroach-write`,
   `SCS_MOD_DB_SECTION=cockroach-write`, `NBA_DB_SECTION=cockroach-read`.
3. Point dashboard logging back to `cockroach-write`.
4. Data written to the Jetson after the cutover would need a reverse copy; the
   longer the window, the larger that copy.

Do not run `sql/indexes/postgres.sql` against Cockroach. Do not read the Jetson
customer tables as authoritative; Cockroach remains their writer.
