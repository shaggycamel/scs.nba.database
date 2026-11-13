-- Read-only view over fty.matchup_result for the data build.
CREATE OR REPLACE VIEW fty.matchup_result_vw AS
SELECT
    season,
    platform,
    league_id,
    matchup,
    competitor_id,
    opponent_id,
    score,
    opponent_score,
    cat_won,
    cat_lost,
    cat_tied,
    result
FROM fty.matchup_result;
