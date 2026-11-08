CREATE OR REPLACE VIEW fty.free_agents_vw AS

-- free_agents.player_id holds the PLATFORM's player id (e.g. ESPN 3202 = Kevin Durant),
-- so it is exposed as fantasy_id and the real nba player_id is resolved via player_vw.

SELECT
    fa.season,
    fa.platform,
    fa.league_id,
    plyr.player_id,
    fa.player_id AS fantasy_id,
    plyr.player_name,
    fa.player_team,
    fa.player_injury_status,
    fa.player_position
FROM fty.free_agents fa
    LEFT JOIN fty.player_vw plyr
        ON plyr.platform = LOWER(fa.platform)
       AND plyr.fantasy_id = fa.player_id
