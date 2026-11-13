-- Public read-only view over the private model table. player_name is the
-- conformed name from util.player_id_map_vw; raw_name is the model's stored name.
CREATE OR REPLACE VIEW mod.team_hierarchy_vw AS
SELECT
    b.game_date,
    b.game_id,
    b.team_id,
    b.player_id,
    b.season,
    b.team_abbreviation,
    b.opponent,
    b.home,
    nm.conformed_name AS player_name,
    b.player_name AS raw_name,
    b.position,
    b.position_depth,
    b.height_cm,
    b.report_status,
    b.p_play,
    b.minutes_if_plays,
    b.expected_minutes,
    b.expected_usage,
    b.depth_rank,
    b.available_rank,
    b.rank_improvement,
    b.expected_vacated_minutes,
    b.expected_vacated_minutes_same_position,
    b.generated_at,
    b.model_cutoff,
    b.model_version
FROM mod.team_hierarchy_base b
LEFT JOIN util.player_id_map_vw nm ON nm.nba_id = b.player_id;
