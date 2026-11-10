# View Name Cleanup Instructions

Status: 2026-11-11. Branch: `views-cleanup`.

Goal: every display-name column in the `nba` view layer uses
`util.player_id_map_vw.conformed_name`, with a raw-name fallback where the
crosswalk is missing.

## Files changed on this branch

- `sql/views/nba/injuries_vw.sql`
- `sql/views/nba/player_box_score_vw.sql`
- `sql/views/nba/team_roster_vw.sql`
- `sql/views/nba/player_info_vw.sql`
- `sql/views/nba/play_by_play_vw.sql`
- `sql/views/nba/latest_team_roster_vw.sql`

The display-name resolution is:

```sql
COALESCE(nm.conformed_name, <raw source name>)
```

`util.player_directory_vw` is intentionally **not** changed: its `source_name`
column is a per-platform directory name, not a display name. Changing it would
break the id crosswalk.

## Current local status

Applied to local Postgres and verified:

| View | Rows | Null player names |
|---|---:|---:|
| `injuries_vw` | 63,767 | 0 |
| `player_box_score_vw` | 722,633 | 0 |
| `team_roster_vw` | 10,875 | 0 |
| `player_info_vw` | 7,248 | 0 |
| `play_by_play_vw` | 8,195,575 | 0 |
| `latest_team_roster_vw` | 9,657 | 0 |

Cockroach currently has the `injuries_vw` fallback applied; the other five view
files still need to be applied there.

## Ordered steps

1. **Review the diff:**
   ```bash
   git diff -- sql/views/nba
   ```
2. **Confirm local Postgres has the latest files applied.** Re-apply the six
   files through `Database('postgres')` if needed.
3. **Verify null names and row counts** on local Postgres:
   ```sql
   SELECT count(*), count(*) FILTER (WHERE player_name IS NULL)
   FROM nba.<view>;
   ```
4. **Apply the six files to Cockroach** through `cockroach-write`, then run
   `db.regrant_read()` so `kobe_public` keeps `SELECT`.
5. **Verify on Cockroach** with `cockroach-read`:
   - zero null display names;
   - row counts unchanged;
   - `kobe_public` grants present.
6. **Watch for view type changes.** `CREATE OR REPLACE` cannot change an
   existing column's type. If it fails, drop/recreate the view and regrant.
   - `player_box_score_vw`, `team_roster_vw`, `injuries_vw`, and
     `player_info_vw` use `character varying` player-name columns.
   - `play_by_play_vw` and `latest_team_roster_vw` use `text`.
7. **Pull the database repo on the NUC** after push. No image rebuild is needed
   for SQL-only view changes.
8. **Then** return to the injury `views-fetch` branch and run the view-only
   parity build.

## Notes

- `latest_team_roster_vw` is marked retired in its file but is still recreated
  by `scripts/apply_views.py`. Either keep it conformed or remove it from the
  apply glob in a separate cleanup.
- `injuries_vw` was the critical fix: without the raw-name fallback, 11,408
  report rows had null `player_name` and the build dropped most of them.
- The box view still has 29 historical cross-team extras; that is accepted for
  the injury model.
