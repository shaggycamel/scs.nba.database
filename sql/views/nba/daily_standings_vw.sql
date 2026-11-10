CREATE OR REPLACE VIEW nba.daily_standings_vw AS

-- Deterministic daily regular-season standings, one row per team per date.
-- Dense in dates: a team that did not play carries its record forward.
--
-- Grain: (season, game_date, team_slug)
--
-- This view is the shared, deterministic layer only. Elimination/clinch
-- status and the simulated playoff-hope probabilities stay in the Python
-- model, where the Monte Carlo simulation and its seeded tie-breaks live.
--
-- conference_rank and games_behind use wins first, then losses, then team_slug
-- for a stable order. They are not the NBA's official multi-step tiebreakers.

WITH scheduled AS (
    SELECT season, game_date, game_id, team
    FROM nba.league_game_schedule_vw
    WHERE season_type = 'Regular Season'
),
results AS (
    SELECT season, game_date, game_id, team, team_winner
    FROM nba.league_game_schedule_vw
    WHERE season_type = 'Regular Season'
      AND team_winner IS NOT NULL
),
team_results AS (
    SELECT season,
           game_date,
           team AS team_slug,
           MAX(CASE WHEN team_winner = team THEN 1 ELSE 0 END) AS won
    FROM results
    GROUP BY season, game_date, team
),
season_games AS (
    SELECT season,
           team AS team_slug,
           -- The 2026-27 schedule is currently incomplete (80 games per team).
           -- The NBA regular season has been 82 games from 2021-22 onward, so
           -- pin it rather than letting a missing schedule row shorten the
           -- season. Earlier seasons keep their observed game count (lockouts).
           CASE WHEN season >= '2021-22' THEN 82 ELSE COUNT(*) END AS season_games
    FROM scheduled
    GROUP BY season, team
),
dates AS (
    SELECT DISTINCT season, game_date FROM results
),
teams AS (
    SELECT DISTINCT season, team_slug FROM team_results
),
grid AS (
    SELECT d.season, d.game_date, t.team_slug
    FROM dates d
    JOIN teams t ON t.season = d.season
),
filled AS (
    SELECT g.season,
           g.game_date,
           g.team_slug,
           r.won,
           SUM(r.won) OVER (
               PARTITION BY g.season, g.team_slug
               ORDER BY g.game_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS wins,
           COUNT(r.won) OVER (
               PARTITION BY g.season, g.team_slug
               ORDER BY g.game_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS played
    FROM grid g
    LEFT JOIN team_results r
      ON r.season = g.season
     AND r.game_date = g.game_date
     AND r.team_slug = g.team_slug
),
base AS (
    SELECT f.season,
           f.game_date,
           f.team_slug,
           t.conference,
           COALESCE(f.wins, 0)::INT8 AS wins,
           COALESCE(f.played, 0)::INT8 AS played,
           s.season_games::INT8 AS season_games,
           (s.season_games - COALESCE(f.played, 0))::INT8 AS games_left,
           (COALESCE(f.wins, 0) + s.season_games - COALESCE(f.played, 0))::INT8 AS max_wins
    FROM filled f
    JOIN nba.teams_vw t ON t.team_slug = f.team_slug
    JOIN season_games s ON s.season = f.season AND s.team_slug = f.team_slug
),
with_losses AS (
    SELECT *, played - wins AS losses
    FROM base
),
ranked AS (
    SELECT *,
           RANK() OVER (
               PARTITION BY season, game_date, conference
               ORDER BY wins DESC, losses ASC
           ) AS conference_rank,
           ROW_NUMBER() OVER (
               PARTITION BY season, game_date, conference
               ORDER BY wins DESC, losses ASC, team_slug
           ) AS _leader_row
    FROM with_losses
),
leaders AS (
    SELECT season, game_date, conference, wins AS leader_wins, losses AS leader_losses
    FROM ranked
    WHERE _leader_row = 1
)
SELECT r.season,
       r.game_date,
       r.team_slug,
       r.conference,
       r.wins,
       r.played,
       r.losses,
       r.wins::FLOAT8 / NULLIF(r.played, 0)::FLOAT8 AS win_pct,
       r.season_games,
       r.games_left,
       r.max_wins,
       r.conference_rank,
       ((l.leader_wins - r.wins) + (r.losses - l.leader_losses))::FLOAT8 / 2.0 AS games_behind
FROM ranked r
JOIN leaders l
  ON l.season = r.season
 AND l.game_date = r.game_date
 AND l.conference = r.conference
