-- Public read view over the private availability curve.
--
-- One row per (prediction date, spell, future game): the probability the
-- player is available for that game, from the injury-duration hazard model.
-- The hierarchy uses it only where the injury report has not reached the game
-- date yet; a report always wins.
CREATE OR REPLACE VIEW mod.injury_game_availability_vw AS
SELECT
    b.prediction_date,
    b.spell_id,
    b.game_id,
    b.player_id,
    nm.conformed_name AS player_name,
    b.player_name AS raw_name,
    b.season,
    b.team_slug,
    b.game_date,
    b.step,
    b.p_available,
    b.model_trained_through,
    b.model_created_at,
    b.generated_at
FROM mod.injury_game_availability_base b
LEFT JOIN util.player_id_map_vw nm ON nm.nba_id = b.player_id;
