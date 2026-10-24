# Injury game_id recovery plan (2026-27)

## Goal

Restore `nba.league_game_schedule` for 2026-27 and fill `nba.injuries.game_id`, so
`nba.player_box_score_vw.inj_status` is populated again and H2H past cells get their
`Out` marker. Fix the upstream cause so a failed schedule fetch can never wipe a season.

## Status (2026-10-24)

Completed:

- `get_game_schedule` now sources `ScheduleLeagueV2` (001/002/004 only,
  strict team filter, non-empty guard); 2026-27 restored to 2,532 rows /
  1,266 games on cockroach-write.
- `nba.schedule_vw` reverted to `nba.league_game_schedule` (source column
  dropped).
- `nba.injuries` cleared and recollected for US dates 2026-10-20..23;
  213 rows, all with `game_id`. The Oct 23 report also wrote 16 rows for
  Oct 24 game dates.
- `get_player_box_score`/`get_team_box_score` now select completed scheduled
  games missing from their base tables; the 2026-27 gaps were backfilled.
- `nba.player_box_score_vw` key_dates join aggregates to one row per season;
  duplicate groups for 2026-10-20 dropped from 121 to 0 on cockroach-write.

Still open:

- NUC image rebuild and unpausing `nba.get_game_schedule` (SSH to the NUC is
  currently refused).
- postgres is not yet aligned with cockroach.

## Current state at start (2026-10-23)

- `nba.injuries`: 163 rows from 2026-10-20..23, every `game_id` NULL
  (16 / 80 / 12 / 55 per day).
- `nba.league_game_schedule` 2026-27: only 134 preseason rows (67 games), all
  2026-10-03..2026-10-16. No regular-season rows.
- `nba.player_box_score` retains at least game 22600001 (DET-BOS); the view exposes no
  2026-27 regular-season rows because it is built on `league_game_schedule`.
- `nba.schedule_vw` uses `statyx.schedule` for seasons > 2025-26, so the dashboard
  schedule looks correct. This masks the gap.
- `ScheduleLeagueV2(league_id="00", season="2026-27")` returns 1,274 games
  (2026-10-03..2027-04-11): 67 preseason, 1,206 regular season, 1 NBA Cup. IDs are
  NBA IDs (`0022600001` -> `22600001`). For 2025-26 it returns 1,400 games including
  playoffs, All-Star, play-in and NBA Cup.
- `LeagueGameLog(season=2026)` currently returns 0 regular-season rows and only the
  134 preseason rows, so it cannot supply the missing regular season.
- The static schedule CDN returns HTTP 403 from this host
  (`scs_hub/known_failures.md:263-268`).

## Root cause

1. `NBAComponent.get_game_schedule` (`scs_hub/src/scs_hub/nba.py:653-691`) does a
   full-season replace: `delete_where(season)` then write `played + upcoming`. When the
   CDN fails, `_upcoming_games` returns `None`; the full path substitutes an empty frame,
   so the partial `played` frame (preseason only) becomes the whole season. This wiped the
   2026-27 regular-season rows.
2. `NBAComponent.get_team_injuries` (`nba.py:186-279`) maps `game_id` from
   `league_game_schedule` on `(game_date, matchup)`. With no schedule row it writes NULL,
   and it only refreshes the current report date, so older NULLs are never repaired.
3. `nba.player_box_score_vw` joins injuries on `game_id`
   (`database/sql/views/nba/player_box_score_vw.sql:143`), so NULL game IDs silently drop
   `inj_status`. H2H past then has no `*`.
4. Related: `get_player_box_score`/`get_team_box_score` select games with
   `game_date > max(view date)`. A missing game on the max date (e.g. 22600002/03 on
   2026-10-20) is never backfilled.

## Changes

### 1. scs_hub: use the NBA schedule API

In `scs_hub/src/scs_hub/nba.py`:

- Add `_api_schedule(season)`:
  - Call `nba_ep.scheduleleaguev2.ScheduleLeagueV2(league_id="00", season=season)`.
  - Transform `SeasonGames` into two `league_game_schedule` rows per game:
    home `HOME vs. AWAY` (`home=True`), away `AWAY @ HOME` (`home=False`).
  - Output columns: `season`, `season_type`, `game_id` (int), `game_date`,
    `matchup`, `team`, `opponent`, `home`, `team_winner`, `team_loser`.
  - `season_type` from the `gameId` prefix: `001` Pre Season, `002` Regular Season,
    `003` All Star, `004` Playoffs, `005` Playoffs (Play-In), `006` Regular Season
    (NBA Cup). Fall back to `nba.key_dates` for an unknown prefix.
  - Set winner/loser only when `gameStatus == 3` and both scores are present.
  - Drop rows with unknown/empty team tricodes; apply the existing `ctx.nba_teams` filter.
  - Log and return `None` on any API/parse failure.
- In `get_game_schedule`:
  - Try `_api_schedule(season)` first; on a non-empty frame, replace the season and log
    `source=scheduleleaguev2`.
  - Otherwise keep `_played_games` + `_upcoming_games` as fallback.
  - In the fallback, if `_upcoming_games` returns `None` or the combined frame is empty:
    read the stored season; if `played` is non-empty, merge
    `stored + played` with `unique(subset=["game_id", "team"], keep="last")` and write;
    if `played` is empty, log and return without deleting.
  - Never call `delete_where` until a non-empty frame is ready. Prefer a single
    transaction for delete + append (same pattern as `Database.deduplicate_tables`).
  - Keep the `upcoming_only=True` skip-on-CDN-failure behaviour.
- Add a `known_failures.md` entry for the destructive full refresh.

### 2. scs_hub: repair injuries.game_id

- In `get_team_injuries`, delete by `(game_date, matchup, player_name)` instead of the
  `game_id`/`game_id IS NULL` predicate. This removes a stale NULL row when the same
  report is refreshed later with a real ID.
- Add `_backfill_injury_game_ids(since)` and call it after the write:
  ```sql
  UPDATE nba.injuries AS i
  SET game_id = (
    SELECT g.game_id
    FROM nba.league_game_schedule AS g
    WHERE g.game_date = i.game_date
      AND g.matchup = i.matchup
      AND g.matchup LIKE '%@%'
    LIMIT 1
  )
  WHERE i.game_id IS NULL
    AND i.game_date >= DATE '<since>';
  ```
  Use `since = dt_est - 30 days` in the scheduled path; log the affected count. Test on
  `postgres` before `cockroach-write`.

### 3. scs_hub: fix the box-score backfill gap

- In `get_player_box_score` and `get_team_box_score`, select scheduled games not already
  in the base table instead of `game_date > max(view date)`:
  ```sql
  SELECT DISTINCT g.game_id
  FROM nba.league_game_schedule g
  WHERE g.game_date <= '<ctx.date_est>'
    AND NOT EXISTS (
      SELECT 1 FROM nba.player_box_score p WHERE p.game_id = g.game_id
    )
  ```
  Use `nba.team_box_score` for the team job. This fills the missing 2026-10-20 games and
  avoids duplicate appends.

### 4. nba/database: pin and deploy

- Commit and push the `scs_hub` change; note the new SHA.
- In `/Users/fred/shaggy_camel_sports/nba/database`:
  - `uv lock --upgrade-package scs-hub`
  - confirm `uv.lock` points at the new SHA
  - commit `uv.lock` and push
- On the NUC:
  ```bash
  cd ~/shaggy_camel_sports/nba/database
  git pull
  docker build -t scs.nba.database:latest .
  DB_CON=cockroach-write ./cron.sh daily
  ```

### 5. Repair the current data

- Back up `nba.league_game_schedule` and `nba.injuries` to the `scratch` schema (not in
  `TRANSPORT_SCHEMAS`) or to CSV. Do not leave backup tables in `nba`; `transport_from`
  would move them.
- Run `nba.get_game_schedule()` with the fixed image. Verify 2026-27 has 2,548 team rows
  (1,274 games) and Regular Season starts 2026-10-20.
- Run `nba.get_team_injuries()` once. The new backfill should set all 163 NULL IDs.
- Run `nba.get_player_box_score()` and `nba.get_team_box_score()` with the fixed
  selectors. Verify all 2026-10-20 games (22600001-03) have base rows.
- Rebuild the dashboard base (`_generate_base.R`) and league data, or wait for the next
  daily deploy. Verify `dfs_h2h_past` has non-NA `inj_status` for 2026-10-20/21.

## Verification

```sql
-- schedule
SELECT season_type, count(*) AS team_rows, min(game_date), max(game_date)
FROM nba.league_game_schedule
WHERE season = '2026-27'
GROUP BY 1 ORDER BY 1;

-- injuries: expect 16/16, 80/80, 12/12, 55/55
SELECT game_date, count(*) AS rows, count(game_id) AS with_id
FROM nba.injuries
WHERE game_date >= '2026-10-20'
GROUP BY 1 ORDER BY 1;

-- box-score injury join
SELECT game_date, count(*) AS rows, count(inj_status) AS with_status
FROM nba.player_box_score_vw
WHERE season = '2026-27' AND game_date >= '2026-10-20'
GROUP BY 1 ORDER BY 1;

-- spot check
SELECT game_date, player_name, team, inj_status
FROM nba.player_box_score_vw
WHERE season = '2026-27' AND game_date = '2026-10-20' AND inj_status = 'Out';
```

- `util.update_log` rows for `nba.get_game_schedule`, `nba.get_team_injuries` and
  `nba.get_player_box_score` are `success = true`.
- App check: `dfs_h2h_past` rows for 2026-10-20/21 have `inj_status`; H2H table shows `*`.

## Rollback

- Revert the `scs_hub` commit and pin `uv.lock` back to `3b44504`; rebuild the image.
- Restore the schedule/injuries backups if the repair maps incorrectly. The injury
  backfill is idempotent and only touches NULLs.
- The API schedule path is additive; the existing played/upcoming code remains as
  fallback.

## Do not

- Do not run the current `get_game_schedule` against `cockroach-write` before the fix; it
  can wipe the season again.
- Do not backfill `game_id` from `statyx.schedule`: those are 9-digit Statyx IDs, not NBA
  IDs.
- Do not remove `game_id` from the `player_box_score_vw` injury join: `nba.injuries` has
  379 duplicate `(game_date, team, nba_id)` groups (1,103 extra rows), so a
  date/team/player join can multiply box-score rows. If changed, dedupe first.
- Do not commit or print credentials.

## Preserve existing work

- `nba/database` has uncommitted changes in `README.md` and
  `scripts/manual_update.py`; leave them untouched.
- `scs_hub` is clean; do not stage unrelated files.
