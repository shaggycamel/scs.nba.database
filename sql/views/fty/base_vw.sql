CREATE OR REPLACE VIEW fty.base_vw AS

SELECT
    lc.season,
    lc.platform,
    lc.league_id,
    lc.competitor_id,
    lc.competitor_abbrev,
    lc.competitor_name,
    lg.league_name,
    lc.division_id,
    lc.division_name,
    lg.starter_count
FROM fty.league_competitor lc
    LEFT JOIN fty.league lg
        ON lc.league_id = lg.league_id
       AND lc.season = lg.season
       AND lc.platform = lg.platform
ORDER BY LOWER(lc.competitor_name)
