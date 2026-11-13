-- Read-only view over fty.customer_league for the entry app.
CREATE OR REPLACE VIEW fty.customer_league_vw AS
SELECT
    customer_id,
    season,
    platform,
    league_id,
    competitor_id
FROM fty.customer_league;
