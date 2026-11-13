-- Read-only view over fty.league_competitor for the entry app.
CREATE OR REPLACE VIEW fty.league_competitor_vw AS
SELECT
    season,
    platform,
    league_id,
    competitor_id,
    competitor_abbrev,
    competitor_name,
    division_id,
    division_name
FROM fty.league_competitor;
