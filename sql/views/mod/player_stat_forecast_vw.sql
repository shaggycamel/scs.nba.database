-- Public read-only view over the latest player-stat snapshot.
--
-- One row per (game_date, game_id, team_id, player_id): the newest
-- prediction_date for that fixture. The base table keeps one snapshot per run
-- date so horizon accuracy can be measured later; consumers normally want this
-- view. `horizon_days` is game_date - prediction_date.
--
-- Every stat is conditional on the player taking the floor. `minutes_if_plays`
-- is the exposure; `expected_minutes` includes the DNP zeros and is carried
-- only for context. Multiply by `p_play` to form an ex-ante expected value.
CREATE OR REPLACE VIEW mod.player_stat_forecast_vw AS
WITH latest AS (
    SELECT
        b.*,
        row_number() OVER (
            PARTITION BY b.game_date, b.game_id, b.team_id, b.player_id
            ORDER BY b.prediction_date DESC, b.generated_at DESC
        ) AS rn
    FROM mod.player_stat_forecast_base b
)
SELECT
    prediction_date,
    horizon_days,
    game_date,
    game_id,
    team_id,
    player_id,
    season,
    team_abbreviation,
    opponent,
    home,
    player_name,
    p_play,
    minutes_if_plays,
    expected_minutes,
    expected_usage,
    pred_fga,
    pred_fgm,
    pred_fg3a,
    pred_fg3m,
    pred_fta,
    pred_ftm,
    pred_oreb,
    pred_dreb,
    pred_ast,
    pred_stl,
    pred_blk,
    pred_tov,
    pred_pf,
    pred_pts,
    pred_reb,
    model_version,
    model_cutoff,
    generated_at
FROM latest
WHERE rn = 1;
