# fty roster/division capture — deploy record

Last updated: 2026-10-28

The ESPN roster/division feature is merged, backfilled and deployed. Both
deploy-time steps were completed on 2026-10-28.

## Current state

- NUC image rebuilt from database `eab3060` / scs-hub `7f9e831` on
  2026-10-28; the old image was removed.
- `fty.get_league` and `fty.get_league_competitor` are on
  `util.update_schedule` as `weekly` rows with `pause = false`.
- The 2026-10-28 weekly run succeeded: `fty.get_league` wrote 4 rows and
  `fty.get_league_competitor` wrote 48; all roster/division fields remain
  populated.
- `scs_hub` main: `7f9e831` (PR #5).
  - `fty.get_league` now returns `roster_size` and `starter_count`.
  - `fty.get_league_competitor` now returns `division_id` and `division_name`.
  - ESPN's default single division is normalised to NULL, so only leagues with
    two or more divisions retain values.
- `nba/database` main: `5815405` (PR #6).
  - DDL: `sql/tables/fty.roster_metadata.sql`.
  - Views: `fty.base_vw` and `fty.roster_schedule_vw` expose the division fields.
  - `scs-hub` pin is back on main (`7f9e831`); the temporary rev pin was removed.
- CockroachDB and local postgres already have:
  - `fty.league.roster_size` / `starter_count`, populated for all 10 league-seasons.
  - `fty.league_competitor.division_id` / `division_name`; only
    `2023-24`/`1966813226` (East/West) and `2026-27`/`1440301458` (Group A/B)
    are populated; all other league-seasons are NULL.
  - Both views applied and re-granted.
- `fty.competitor_roster` is unchanged. `lineup_slot`,
  `competitor_roster_size_vw`, and the `util.table_column_order` row were
  deliberately removed.
- Yahoo is removed as a live platform: `yfpy` is gone from both repos and the
  `yahoo_nba.py` handler is deleted. Historical `yahoo_id` mappings and view
  columns remain intentionally.

## Completed step 1 — rebuild/deploy the NUC image

Done 2026-10-28. The image was built from database `eab3060` /
scs-hub `7f9e831` and smoke-tested for the new fty fields. Commands used:

```bash
cd ~/shaggy_camel_sports/nba/database
git pull --ff-only
docker build -t scs.nba.database:latest .
```

## Completed step 2 — add weekly schedule rows

Done 2026-10-28, after the rebuild, on **both postgres and cockroach**. Both
rows exist once with `pause = false`; the first weekly run succeeded.

The idempotent SQL applied:

```sql
INSERT INTO util.update_schedule
    (schema, table_name, associated_function, cadence,
     schema_sequence, function_sequence, pause)
SELECT 'fty', 'league', 'fty.get_league', 'weekly', 3, 1, false
WHERE NOT EXISTS (
    SELECT 1 FROM util.update_schedule
    WHERE associated_function = 'fty.get_league'
);

INSERT INTO util.update_schedule
    (schema, table_name, associated_function, cadence,
     schema_sequence, function_sequence, pause)
SELECT 'fty', 'league_competitor', 'fty.get_league_competitor', 'weekly', 3, 2, false
WHERE NOT EXISTS (
    SELECT 1 FROM util.update_schedule
    WHERE associated_function = 'fty.get_league_competitor'
);
```

`function_sequence` 1/2 puts these before the other fty work. The existing
`fty.get_league_byes` row also uses 1, but the `table_name` tie-break keeps
`league` before `league_byes`; there is no dependency between them.

## Verification after the weekly run (2026-10-28)

- `util.update_schedule` has both rows with `pause = false`.
- `util.update_log` shows successful `fty.get_league` (4 rows) and
  `fty.get_league_competitor` (48 rows) entries.
- `fty.league`: 10/10 rows still have `roster_size` and `starter_count`.
- Divisions remain populated only for `2023-24`/`1966813226` and
  `2026-27`/`1440301458`; postgres matches cockroach (20 division rows).
- `fty.base_vw` returns 114 rows and `fty.roster_schedule_vw` 155,018.
- `yfpy` / `yahoo-oauth` are absent from the rebuilt image.

## Removal

Delete this file once the NUC database image has completed a full scheduled
cycle — the next intraday, daily and weekly runs — with every
`util.update_log` task successful and no errors in `cron.log` or
`docker logs update_tables`. When deleting it, also remove the README link to
this file.
