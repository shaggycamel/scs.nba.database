CREATE OR REPLACE VIEW mod.injury_daily_forecast_vw AS

-- Public read view over the injury model's daily forecast table.
--
-- The base table is written by scs.nba.mod.injury_duration. A daily forecast
-- row is a snapshot, so its actual_* columns are null when the outcome was not
-- known at publication. This view fills them from the live box score and
-- roster once the player returns:
--   * actual return is the first game the player played after injury_start_date
--     in the same season;
--   * missed games follow the player's roster stints, so a mid-absence trade is
--     counted correctly;
--   * return_seen/censored follow that live result.
-- A still-active spell stays null and censored until its return game is played.
--
-- The box lookup uses the raw player_box_score table rather than the expanded
-- view: min > 0 already selects played games, and the raw table makes the
-- live join much faster.

WITH spells AS (
    SELECT spell_id, player_id, season, min(injury_start_date) AS injury_start_date
    FROM mod.injury_daily_forecast_base
    GROUP BY spell_id, player_id, season
),
returns AS (
    SELECT sp.spell_id, min(s.game_date) AS live_return_date
    FROM spells sp
    JOIN nba.player_box_score bx
      ON bx.player_id = sp.player_id
     AND bx.min > 0
    JOIN nba.league_game_schedule_vw s
      ON s.game_id = bx.game_id
     AND s.season = sp.season
    WHERE s.game_date > sp.injury_start_date
    GROUP BY sp.spell_id
),
missed AS (
    SELECT sp.spell_id, count(*) AS live_games_missed
    FROM spells sp
    JOIN returns r ON r.spell_id = sp.spell_id
    JOIN nba.team_roster_vw ro
      ON ro.player_id::BIGINT = sp.player_id
     AND ro.season = sp.season
    JOIN nba.league_game_schedule_vw s
      ON s.team = ro.team_slug
     AND s.season = sp.season
     AND s.game_date >= ro.entry_date
     AND s.game_date < ro.exit_date
    WHERE s.game_date >= sp.injury_start_date
      AND s.game_date < r.live_return_date
    GROUP BY sp.spell_id
)
SELECT
    b.prediction_date,
    b.spell_id,
    b.season,
    b.player_id,
    b.player_name,
    b.team_slug,
    b.injury_start_date,
    b.games_missed_so_far,
    b.days_missed_so_far,
    b.status,
    b.body_region,
    b.ailment_class,
    b.pred_return_date,
    b.pred_return_date_mean,
    b.pred_games_median,
    b.pred_games_mean,
    b.p_next_game,
    b.p_return_7d,
    b.p_return_14d,
    b.p_return_30d,
    COALESCE(b.actual_return_date, r.live_return_date) AS actual_return_date,
    COALESCE(b.actual_games_missed, m.live_games_missed) AS actual_games_missed,
    (COALESCE(b.actual_return_date, r.live_return_date) IS NOT NULL) AS return_seen,
    (COALESCE(b.actual_return_date, r.live_return_date) IS NULL) AS censored,
    b.history_imputed,
    b.censor_reason,
    b.model_trained_through,
    b.model_created_at,
    b.generated_at
FROM mod.injury_daily_forecast_base b
LEFT JOIN returns r ON r.spell_id = b.spell_id
LEFT JOIN missed m ON m.spell_id = b.spell_id
