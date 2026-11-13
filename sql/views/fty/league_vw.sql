-- Read-only view over fty.league for the entry app and the draft data build.
CREATE OR REPLACE VIEW fty.league_vw AS
SELECT
    season,
    platform,
    league_id,
    league_name,
    scoring_type,
    team_count,
    is_public,
    roster_size,
    starter_count
FROM fty.league;
