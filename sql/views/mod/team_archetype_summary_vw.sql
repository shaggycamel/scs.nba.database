-- Public read-only view over the private team archetype summary. One row per
-- team-game-archetype: three shares (rolling expected starters, actual
-- starters, available players) and the top three players for that style.
-- The description is version-specific; historical walk-forward rows are null
-- until their seasonal profiles are added to the lookup.
CREATE OR REPLACE VIEW mod.team_archetype_summary_vw AS
SELECT
    b.season,
    b.game_date,
    b.game_id,
    b.team_id,
    b.team_abbreviation,
    b.archetype,
    b.roster_size,
    b.expected_starter_weight,
    b.expected_share,
    b.actual_starter_share,
    b.available_share,
    b.expected_dominant,
    b.actual_dominant,
    b.top_1_player_id,
    b.top_1_player_name,
    b.top_1_score,
    b.top_2_player_id,
    b.top_2_player_name,
    b.top_2_score,
    b.top_3_player_id,
    b.top_3_player_name,
    b.top_3_score,
    b.model_version,
    b.generated_at,
    l.archetype_description
FROM mod.team_archetype_summary_base b
LEFT JOIN mod.player_archetype_description_base l
    ON l.archetype_label = b.archetype;
