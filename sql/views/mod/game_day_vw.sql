-- The day-of contract: one row per player per upcoming fixture.
--
-- Only unplayed games from the previous Eastern date onward. Availability is
-- the report when one exists for that game date (`report_available`),
-- otherwise the injury-duration curve (`p_play_source = 'injury'`), otherwise
-- the hierarchy's own state-only probability. `p_play_injury` is null when the
-- player has no active spell or the report already covers the game.
--
-- The injury context is the latest published spell row; it is a snapshot as of
-- the latest report, not a per-game forecast.
CREATE OR REPLACE VIEW mod.game_day_vw AS
SELECT
    h.game_date,
    h.game_id,
    h.team_id,
    h.team_abbreviation,
    h.opponent,
    h.home,
    h.season,
    h.player_id,
    nm.conformed_name AS player_name,
    h.position,
    h.depth_rank,
    h.report_status,
    (h.report_status IS NOT NULL) AS report_available,
    h.p_play,
    h.p_play_source,
    h.p_play_injury,
    h.minutes_if_plays,
    h.expected_minutes,
    h.expected_usage,
    h.expected_usage_model,
    h.expected_vacated_minutes,
    h.expected_vacated_minutes_same_position,
    i.spell_id,
    i.injury_start_date,
    i.pred_return_date,
    i.p_next_game,
    i.p_return_7d,
    a.archetype_label,
    a.archetype_confidence,
    h.generated_at,
    h.model_version
FROM mod.team_hierarchy_base h
LEFT JOIN util.player_id_map_vw nm ON nm.nba_id = h.player_id
JOIN nba.league_game_schedule s
  ON s.game_id = h.game_id
 AND s.team = h.team_abbreviation
LEFT JOIN LATERAL (
    SELECT
        f.spell_id,
        f.injury_start_date,
        f.pred_return_date,
        f.p_next_game,
        f.p_return_7d
    FROM mod.injury_daily_forecast_base f
    WHERE f.player_id = h.player_id
    ORDER BY f.prediction_date DESC
    LIMIT 1
) i ON TRUE
LEFT JOIN mod.player_archetype_current_base a ON a.player_id = h.player_id
WHERE s.team_winner IS NULL
  -- The NBA day is Eastern, not UTC: a UTC cutoff drops the evening slate at
  -- tip-off. Keep the previous Eastern date so the current slate survives the
  -- midnight rollover.
  AND h.game_date >= (CURRENT_TIMESTAMP AT TIME ZONE 'America/New_York')::date - 1;
