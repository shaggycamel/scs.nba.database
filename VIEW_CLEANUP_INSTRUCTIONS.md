# View Name Cleanup Instructions

Status: 2026-11-10. Branch: `main` (merged from `views-cleanup` at `aee62c5`).

Goal: every view in the `nba` view layer exposes two adjacent name columns.
`player_name` is the display name from
`util.player_id_map_vw.conformed_name`; `raw_name` is the original source
name. There is no fallback: when the crosswalk is missing, `player_name` is
NULL and `raw_name` still carries the source value. `raw_name` always sits
immediately after `player_name`.

## Files changed

- `sql/views/nba/injuries_vw.sql`
- `sql/views/nba/player_box_score_vw.sql`
- `sql/views/nba/team_roster_vw.sql`
- `sql/views/nba/player_info_vw.sql`
- `sql/views/nba/play_by_play_vw.sql`
- `sql/views/nba/latest_team_roster_vw.sql`

The name columns are:

```sql
nm.conformed_name AS player_name,
<raw source name> AS raw_name
```

`util.player_directory_vw` is intentionally **not** changed: its `source_name`
column is a per-platform directory name, not a display name. Changing it would
break the id crosswalk.

## Column sources

| View | `player_name` | `raw_name` |
|---|---|---|
| `injuries_vw` | `nm.conformed_name` | `inj.player_name` |
| `player_box_score_vw` | `nm.conformed_name` | `tr.player` |
| `team_roster_vw` | `nm.conformed_name` | `tr.player` |
| `player_info_vw` | `nm.conformed_name` | `player_info.first_name \|\| ' ' \|\| player_info.last_name` |
| `play_by_play_vw` | `nm.conformed_name` | `pbp.player_name` |
| `latest_team_roster_vw` | `nm.conformed_name` | `tr.player` |

`player_box_score_vw` uses `tr.player`, not `pbs.player_name`: the view starts
from schedule × roster stints and `LEFT JOIN`s the box score, so
`pbs.player_name` is NULL on stat-less rows, while `tr.player` is always
populated and matches `team_roster_vw`. On `latest_team_roster_vw` the existing
`player` column is renamed to `player_name` so every view uses the same names.

## Current status

The six files are on `main` at commit `aee62c5` and were applied to the real
Cockroach views on 2026-11-10. All six were dropped and recreated (a mid-view
`raw_name` and the `latest_team_roster_vw.player` rename make `CREATE OR
REPLACE` insufficient), then `db.regrant_read()` ran. `kobe_public` can
`SELECT` all six through `cockroach-read`.

Local Postgres is still not running on this host, so it has neither the new
views nor the injury backfill. The old local fallback build had these row
counts; expect small drift when it is re-verified:
63,767 injuries; 722,633 box score; 10,875 team roster; 7,248 player info;
8,195,575 play-by-play; 9,657 latest roster.

A one-off backfill on 2026-11-10 filled 11,429 of the 11,435 null `nba_id`
values in `nba.injuries`; 6 rows remain (Kyle Mangas 5, Jeenathan Williams 1).
The pre-update values are in `scratch.injuries_nba_id_backup_20261110`.

On 2026-11-10 the `player_box_score_vw` and `team_roster_vw` season windows
were widened from regular season only to the full schedule (preseason,
regular season and playoffs). The injury model needs playoff box rows, and the
regular-season-only window was censoring playoff returns. `player_box_score_vw`
now has 810,633 rows. Both views were reapplied to Cockroach and
`db.regrant_read()` ran again.

## Completeness (Cockroach live views, 2026-11-10)

Measured after the apply and the injury backfill, against the real view
definitions.

| View | Rows | Null `player_name` | Null `raw_name` |
|---|---:|---:|---:|
| `injuries_vw` | 64,269 | 6 | 0 |
| `player_box_score_vw` | 810,633 | 615 | 0 |
| `team_roster_vw` | 10,949 | 10 | 0 |
| `player_info_vw` | 7,248 | 3,140 | 1 |
| `play_by_play_vw` | 8,259,647 | 675,740 | 0 |
| `latest_team_roster_vw` | 9,658 | 7 | 0 |

Where the nulls come from:

- `injuries_vw`: before the 2026-11-10 backfill, 11,435 rows across 407
  distinct raw names had `nba_id IS NULL`. The backfill resolved 11,429 of
  them by combining the id already attached to the same name elsewhere in
  `nba.injuries` (2,410 rows), `util.active_player_vw` aliases with
  punctuation/accent folding (8,985 rows), and five explicit report-name
  aliases (34 rows). Six rows across two names remain (Kyle Mangas 5,
  Jeenathan Williams 1). Note that `active_player_vw` is a per-season fetch-id
  view, not a general name directory; it covered 400/407 names because
  `player_directory_vw` already contains most of them.
- `player_box_score_vw` / `team_roster_vw` / `latest_team_roster_vw`: 615 / 10 /
  7 rows over the same four source ids — Chris Johnson, Chris Wright, Mike
  James and Tony Mitchell. The 615 includes the playoff/preseason rows added
  when the box view's season window was widened. All four exist in
  `util.player_source_id`, but each `player_key` has two NBA ids and
  `player_id_map_vw` exposes only one, so the join misses the other. Across
  util, 39 player keys carry two NBA ids.
- `player_info_vw`: 3,140 rows. 3,135 are inactive historical players absent
  from util altogether (all `rosterstatus = 'Inactive'`, from the 2024-25
  snapshot); the other 5 are the shadowed ids above (plus Marcus Williams).
- `play_by_play_vw`: 675,740 view rows, which is 337,989 base rows doubled by
  the schedule join. Of the base rows: 245,329 carry a team id, 70,904 carry
  `person_id = 0` (neither is a player-name gap), 16,758 are NBA-range player
  ids across 892 ids (891 of which util does not know), and 4,998 are G-League
  range across 171 ids. Only 295 rows (Mike James) are a shadowed id.

`util.unmatched_player_source_vw` is empty: every source id in
`util.player_directory_vw` is already registered in `util.player_source_id`.
This is not a source-registration gap; it is the map's one-row-per-player
grain plus players util has never loaded.

The play-by-play counts are also inflated by a pre-existing join problem:
`nba.league_game_schedule` has 48,932 rows for 24,466 distinct games, so the
view's join on `game_id` duplicates each play. This is unrelated to the name
change, but it doubles any row-count check on that view.

## Follow-up: expanding the util names view

1. **Expose every source id, not one chosen id per player.** A new view (for
   example `util.player_source_xref_vw`) keyed by `(platform, source_id)` with
   `player_key` and `conformed_name` would fix the four shadowed ids and the
   rows above. Changing `player_id_map_vw` itself to that grain would break
   consumers that expect one row per player.
2. **Add a dedicated name view.** `util.active_player_vw` is a per-season
   fetch-id view, not a general name directory; it only covers names present in
   `player_directory_vw` and happens to resolve 400/407 injury names. Use that
   coverage as the seed for a `util.player_name_vw` keyed by normalized/alias
   name → `player_key`, `conformed_name` and `nba_id`, rather than overloading
   `active_player_vw`. The one-off backfill hard-coded five aliases (Jeff
   Dowtin, Jr. Udeh, Christopher Cenac Jr., Kenyon Martin Jr., David Jones);
   move those into the view so future reports resolve them. Kyle Mangas still
   has no util row or NBA id, and Jeenathan Williams has no NBA link. Also fold
   punctuation when matching report names so `P.J. Dozier` finds `PJ Dozier`.
3. **Decide whether to ingest historical players.** 3,135 inactive
   `nba.player_info` entries are absent from util; loading them is a data
   decision, not a view fix.
4. **Exclude non-player play-by-play rows from coverage metrics.** Team ids and
   `person_id = 0` account for 316,233 of the 337,989 base nulls. The remaining
   ~21,756 rows are mostly untracked players that util would have to load.

## Deployment record

Done on 2026-11-10:

- Reviewed the diff and rewrote the six SQL files to the two-column form.
- Applied all six to Cockroach (`cockroach-write`) with drop/recreate.
- Ran `db.regrant_read()`; verified `kobe_public` SELECT access on all six
  through `cockroach-read`.
- Committed as `aee62c5` and pushed to `main` and `views-cleanup`.
- Backfilled `nba.injuries.nba_id` (11,429 of 11,435 rows; 6 remain).
- Widened `player_box_score_vw` and `team_roster_vw` to the full schedule
  window so playoff and preseason games are covered; reapplied both to
  Cockroach and regranted.
- Rebuilt `nba.team_roster` from box score, roster snapshots and injury-report
  stints. The report adds the missing new-team stint for players traded while
  injured who never played for that team (for example De'Anthony Melton,
  2024-25: GSW exits 2024-12-16, BKN enters 2024-12-16). The table is now
  10,949 stints with 0 missing box stints, 0 missing report stints, 0 invalid
  windows and 0 overlaps.
- Added `start_position` to `player_box_score_vw` (at the end of the column
  list) for the injury model's rotation features; reapplied and regranted.

Remaining:

1. **Start local Postgres and apply the six files.** Drop each view first
   (check for dependants with `DROP VIEW ... RESTRICT`), then apply through
   `Database('postgres')`. `scripts/apply_views.py` alone is not enough.
2. **Verify null names and row counts** on local Postgres:
   ```sql
   SELECT count(*),
          count(*) FILTER (WHERE player_name IS NULL) AS null_player_name,
          count(*) FILTER (WHERE raw_name IS NULL) AS null_raw_name
   FROM nba.<view>;
   ```
   `raw_name` should be populated on every row; `player_name` may be NULL only
   where the crosswalk is missing. Expect the local gaps to resemble the
   Cockroach findings above.
3. **Pull the database repo on the NUC.** No image rebuild is needed for
   SQL-only view changes.
4. **Then** return to the injury `views-fetch` branch and run the view-only
   parity build.

If a view must be changed again, note that `CREATE OR REPLACE` cannot insert a
column mid-view or change an existing column's type. Drop/recreate and regrant:

- `player_box_score_vw`, `team_roster_vw`, `injuries_vw`, and
  `player_info_vw` use `character varying` player-name columns.
- `play_by_play_vw` and `latest_team_roster_vw` use `text`.

## Notes

- `latest_team_roster_vw` is marked retired in its file but is still recreated
  by `scripts/apply_views.py`. Either keep it conformed or remove it from the
  apply glob in a separate cleanup.
- `injuries_vw` was the critical case: the old fallback masked 11,435 null
  crosswalks on Cockroach (11,408 in the earlier local build), and the model
  build drops most null-name rows. Those rows now have a null `player_name` by
  design, with the source name preserved in `raw_name`; the injury model must
  use `raw_name` (or coalesce the two) to keep them.
- The box view still has 29 historical cross-team extras; that is accepted for
  the injury model.
- All six views are dropped and recreated, so grants must be reapplied
  (`db.regrant_read()`) and any external consumers relying on column order
  should be checked.
- The pre-rebuild Cockroach definitions were saved to
  `/tmp/opencode/old_nba_views_20261110.sql`; the injury-id pre-update values
  are in `scratch.injuries_nba_id_backup_20261110`.
