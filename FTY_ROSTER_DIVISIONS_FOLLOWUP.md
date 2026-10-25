# fty roster/division capture — remaining work

Last updated: 2026-10-25

The ESPN roster/division feature is merged and the database is already
backfilled. Two deploy-time steps remain, both blocked on NUC access.

## Current state

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

## Remaining step 1 — rebuild/deploy the NUC image

The NUC is still running the pre-feature image. Until it is rebuilt,
`fty.get_league` and `fty.get_league_competitor` are **not** on
`util.update_schedule`, so nothing overwrites the new fields.

On the NUC:

```bash
cd ~/shaggy_camel_sports/nba/database
git pull
docker build -t scs.nba.database:latest .
./cron.sh
```

Confirm the image is built from database main `5815405` / scs-hub `7f9e831`.

## Remaining step 2 — add weekly schedule rows (AFTER the rebuild)

**Do this only after the NUC is running the new image.** The old image's
handlers would rewrite `fty.league` and `fty.league_competitor` rows without the
new columns, setting them back to NULL.

Apply idempotently to **both postgres and cockroach**:

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

## Verification after the weekly run

- `util.update_schedule` has both rows with `pause = false`.
- `util.update_log` shows successful `fty.get_league` and
  `fty.get_league_competitor` rows for the weekly run.
- `fty.league`: 10/10 rows still have `roster_size` and `starter_count`.
- Divisions remain populated only for `2023-24`/`1966813226` and
  `2026-27`/`1440301458`.
- `fty.base_vw` and `fty.roster_schedule_vw` still return rows.
- `yfpy` / `yahoo-oauth` are absent from the rebuilt image.
