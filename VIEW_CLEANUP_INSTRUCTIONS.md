# View Name Cleanup Instructions

Status: 2026-11-11. Branch: `views-cleanup`.

Goal: every view in the `nba` view layer exposes two adjacent name columns.
`player_name` is the display name from
`util.player_id_map_vw.conformed_name`; `raw_name` is the original source
name. There is no fallback: when the crosswalk is missing, `player_name` is
NULL and `raw_name` still carries the source value. `raw_name` always sits
immediately after `player_name`.

## Files changed on this branch

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

The six files are rewritten to the two-column form. Their definitions were
validated by creating them in a throwaway `scratch_views` schema on Cockroach
(`cockroach-write`) and querying them; the schema was dropped afterwards. They
have **not** been applied to the real views yet: local Postgres is not running
on this host, and the Cockroach apply is waiting on the util-name decision
below. Cockroach still has the fallback `injuries_vw`; the other five real
views still have their old definitions.

The old local Postgres build (fallback, before this rewrite) had these row
counts. Expect small drift when it is re-verified:
63,767 injuries; 722,633 box score; 10,875 team roster; 7,248 player info;
8,195,575 play-by-play; 9,657 latest roster.

A one-off backfill on 2026-11-10 filled 11,429 of the 11,435 null `nba_id`
values in `nba.injuries`; 6 rows remain (Kyle Mangas 5, Jeenathan Williams 1).
The pre-update values are in `scratch.injuries_nba_id_backup_20261110`.

## Completeness (Cockroach scratch build, 2026-11-10)

| View | Rows | Null `player_name` | Null `raw_name` |
|---|---:|---:|---:|
| `injuries_vw` | 64,269 | 6 | 0 |
| `player_box_score_vw` | 717,063 | 551 | 0 |
| `team_roster_vw` | 10,877 | 10 | 0 |
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
- `player_box_score_vw` / `team_roster_vw` / `latest_team_roster_vw`: 551 / 10 /
  7 rows over the same four source ids — Chris Johnson, Chris Wright, Mike
  James and Tony Mitchell. All four exist in `util.player_source_id`, but each
  `player_key` has two NBA ids and `player_id_map_vw` exposes only one, so the
  join misses the other. Across util, 39 player keys carry two NBA ids.
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

## Ordered steps

1. **Review the diff:**
   ```bash
   git diff -- sql/views/nba
   ```
2. **Rewrite the six SQL files** to the two-column form: drop every
   `COALESCE(...)` name expression and place `raw_name` directly after
   `player_name`. Done on this branch.
3. **Start local Postgres and apply the six files.** `CREATE OR REPLACE`
   cannot insert a column mid-view, and `latest_team_roster_vw.player` must be
   renamed, so drop each view first (check for dependants with
   `DROP VIEW ... RESTRICT`), then apply through `Database('postgres')`.
   `scripts/apply_views.py` alone is not enough.
4. **Verify null names and row counts** on local Postgres:
   ```sql
   SELECT count(*),
          count(*) FILTER (WHERE player_name IS NULL) AS null_player_name,
          count(*) FILTER (WHERE raw_name IS NULL) AS null_raw_name
   FROM nba.<view>;
   ```
   `raw_name` should be populated on every row; `player_name` may be NULL only
   where the crosswalk is missing. Expect the local gaps to resemble the
   Cockroach findings above.
5. **Apply the six files to Cockroach** through `cockroach-write`, using the
   same drop/recreate sequence, then run `db.regrant_read()` so `kobe_public`
   keeps `SELECT`.
6. **Verify on Cockroach** with `cockroach-read`:
   - row counts unchanged;
   - `raw_name` populated;
   - `player_name` NULLs match the completeness table;
   - `kobe_public` grants present.
7. **Watch for view type changes.** `CREATE OR REPLACE` cannot change an
   existing column's type. If it fails, drop/recreate the view and regrant.
   - `player_box_score_vw`, `team_roster_vw`, `injuries_vw`, and
     `player_info_vw` use `character varying` player-name columns.
   - `play_by_play_vw` and `latest_team_roster_vw` use `text`.
8. **Pull the database repo on the NUC** after push. No image rebuild is needed
   for SQL-only view changes.
9. **Then** return to the injury `views-fetch` branch and run the view-only
   parity build.

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
