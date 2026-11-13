-- Parsed injury reasons joined to the report; the injury model refreshes the map.
-- Player naming comes from nba.injuries_vw: player_name is the conformed name,
-- raw_name is the report's original name.
CREATE OR REPLACE VIEW nba.injuries_parsed_vw AS
SELECT i.game_date, i.game_id, i.matchup, i.team, i.team_slug,
       i.player_name, i.raw_name,
       i.nba_id, i.status, i.reason,
       m.reason_category, m.body_part_raw, m.body_side, m.body_region,
       m.ailment_raw, m.ailment_class, m.is_surgical, m.is_recovery_stage,
       m.is_management, m.is_bone_stress, m.mentions_major_structure,
       m.n_reason_separators, m.reason_len
FROM nba.injuries_vw i
LEFT JOIN nba.injury_reason_map m ON m.reason = coalesce(i.reason, '');
