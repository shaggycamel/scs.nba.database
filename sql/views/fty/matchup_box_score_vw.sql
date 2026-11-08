CREATE OR REPLACE VIEW fty.matchup_box_score_vw AS

-- Long form matchup results, one row per competitor per category.
-- Reads scored categories plus the shooting components (fgm/fga/ftm/fta) from
-- categories_vw, so the ratio z-scores keep their inputs whatever the league scores.
-- A ratio category (fg_pct) is built from its numerator/denominator, which live in
-- matchup_box_score even when the league does not score them; a points league gets
-- fantasy_points instead.

SELECT
    c.season,
    c.platform,
    c.league_id,
    bs.matchup,
    bs.competitor_id,
    c.nba_category AS category,
    c.fmt_category,
    c.display_order,
    c.scoring_type,
    c.scoring_format,
    c.higher_is_better,
    CASE
        WHEN c.is_ratio THEN COALESCE(num.value / NULLIF(den.value, 0), 0)
        ELSE bs.value
    END AS value,
    CASE
        WHEN c.points IS NOT NULL THEN bs.value * c.points
        ELSE NULL::DOUBLE PRECISION
    END AS fantasy_points
FROM fty.categories_vw c
    JOIN fty.matchup_box_score bs
        ON bs.season = c.season
       AND bs.platform = c.platform
       AND bs.league_id = c.league_id
       AND bs.category = COALESCE(c.numerator, c.nba_category)
    LEFT JOIN fty.matchup_box_score num
        ON num.season = c.season
       AND num.platform = c.platform
       AND num.league_id = c.league_id
       AND num.matchup = bs.matchup
       AND num.competitor_id = bs.competitor_id
       AND num.category = c.numerator
    LEFT JOIN fty.matchup_box_score den
        ON den.season = c.season
       AND den.platform = c.platform
       AND den.league_id = c.league_id
       AND den.matchup = bs.matchup
       AND den.competitor_id = bs.competitor_id
       AND den.category = c.denominator
WHERE c.category_role IN ('scored', 'component')
