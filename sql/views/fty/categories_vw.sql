CREATE OR REPLACE VIEW fty.categories_vw AS

-- One row per league per category, tagged with the role that category plays.
--
--   scored    - what the league actually plays, from league_categories
--   component - fgm/fga/ftm/fta. A league that scores FG% usually does not score its
--               components, but matchup_box_score always stores them and never stores
--               the ratio, so they must stay fetchable. calc_z_pcts() needs them for
--               every league regardless of scoring. Suppressed where already scored.
--   derived   - all_cat / fg_z / ft_z. Computed in R, never in league_categories.

-- scored -----------------------------------------------------------------
SELECT
    lc.season,
    lc.platform,
    lc.league_id,
    lc.category                     AS platform_category,
    cl.nba_category,
    cl.fmt_category,
    cl.display_order,
    lc.points,
    cl.higher_is_better,
    cl.numerator,
    cl.denominator,
    cl.numerator IS NOT NULL        AS is_ratio,
    'scored'                        AS category_role,
    lg.scoring_type,
    sf.scoring_format
FROM fty.league_categories lc
    JOIN fty.platform_category pc
        ON pc.platform = lc.platform
       AND pc.platform_category = lc.category
    JOIN fty.category_label cl
        ON cl.nba_category = pc.nba_category
    LEFT JOIN fty.league lg
        ON lg.season = lc.season
       AND lg.platform = lc.platform
       AND lg.league_id = lc.league_id
    LEFT JOIN fty.scoring_format sf
        ON sf.platform = lg.platform
       AND sf.scoring_type = lg.scoring_type::TEXT

UNION ALL

-- component --------------------------------------------------------------
SELECT
    lg.season,
    lg.platform,
    lg.league_id,
    NULL::TEXT                      AS platform_category,
    cl.nba_category,
    cl.fmt_category,
    cl.display_order,
    NULL::DOUBLE PRECISION          AS points,
    cl.higher_is_better,
    cl.numerator,
    cl.denominator,
    FALSE                           AS is_ratio,
    'component'                     AS category_role,
    lg.scoring_type,
    sf.scoring_format
FROM fty.league lg
    CROSS JOIN fty.category_label cl
    LEFT JOIN fty.scoring_format sf
        ON sf.platform = lg.platform
       AND sf.scoring_type = lg.scoring_type::TEXT
WHERE cl.nba_category IN ('fgm', 'fga', 'ftm', 'fta')
  AND NOT EXISTS (
        SELECT 1
        FROM fty.league_categories lc
            JOIN fty.platform_category pc
                ON pc.platform = lc.platform
               AND pc.platform_category = lc.category
        WHERE lc.season = lg.season
          AND lc.platform = lg.platform
          AND lc.league_id = lg.league_id
          AND pc.nba_category = cl.nba_category
  )

UNION ALL

-- derived ----------------------------------------------------------------
SELECT
    lg.season,
    lg.platform,
    lg.league_id,
    NULL::TEXT                      AS platform_category,
    cl.nba_category,
    cl.fmt_category,
    cl.display_order,
    NULL::DOUBLE PRECISION          AS points,
    cl.higher_is_better,
    cl.numerator,
    cl.denominator,
    cl.numerator IS NOT NULL        AS is_ratio,
    'derived'                       AS category_role,
    lg.scoring_type,
    sf.scoring_format
FROM fty.league lg
    CROSS JOIN fty.category_label cl
    LEFT JOIN fty.scoring_format sf
        ON sf.platform = lg.platform
       AND sf.scoring_type = lg.scoring_type::TEXT
WHERE cl.nba_category IN ('all_cat', 'fg_z', 'ft_z')
