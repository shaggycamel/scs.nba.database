CREATE OR REPLACE VIEW util.player_directory_vw AS

-- Every (season, platform, source_id) a player is known by, across nba, statyx and the
-- fantasy platforms. Feeds util.active_player_vw and util.unmatched_player_source_vw.
--
-- The fantasy legs read fty (formerly fty_dev). ESPN coverage is identical between the two
-- schemas across 2023-24/2024-25/2025-26; the Yahoo league is retired, so the 2024-25
-- Yahoo league (121793) no longer appears here. Its id mappings remain in
-- util.player_source_id.

SELECT
    s.season,
    'nba'::TEXT AS platform,
    b.player_id AS source_id,
    b.player_name AS source_name
FROM nba.player_box_score b
    JOIN (
        SELECT DISTINCT game_id, season
        FROM nba.league_game_schedule
    ) s USING (game_id)
WHERE b.player_id IS NOT NULL AND b.player_id < 100000000

UNION

SELECT
    r.season,
    'nba'::TEXT AS platform,
    r.player_id::BIGINT AS source_id,
    r.player AS source_name
FROM nba.team_roster r
WHERE r.player_id IS NOT NULL

UNION

SELECT
    pi.season,
    'statyx'::TEXT AS platform,
    pi.player_id AS source_id,
    pi.full_name AS source_name
FROM statyx.player_info pi
WHERE pi.player_id IS NOT NULL

UNION

SELECT
    fa.season,
    LOWER(fa.platform) AS platform,
    fa.player_id AS source_id,
    fa.player_name AS source_name
FROM fty.free_agents fa
WHERE fa.player_id IS NOT NULL

UNION

SELECT
    cr.season,
    LOWER(cr.platform) AS platform,
    cr.player_fantasy_id AS source_id,
    cr.player_name AS source_name
FROM fty.competitor_roster cr
WHERE cr.player_fantasy_id IS NOT NULL
