CREATE OR REPLACE VIEW fty.matchup_box_score_vw_retired AS

-- Retired: superseded by matchup_box_score_vw, which keeps one row per category.
-- Pivots the long matchup_box_score back to one column per stat.
-- fgm/fga/ftm/fta are emitted whether or not the league scores them: calc_z_pcts() in
-- the R package needs them for every league, and the fg_pct/ft_pct ratios are derived
-- here rather than stored.

SELECT
    bs.season,
    bs.platform,
    bs.league_id,
    bs.competitor_id,
    bs.matchup,
    MAX(bs.value) FILTER (WHERE bs.category = 'pts')   AS pts,
    MAX(bs.value) FILTER (WHERE bs.category = 'blk')   AS blk,
    MAX(bs.value) FILTER (WHERE bs.category = 'stl')   AS stl,
    MAX(bs.value) FILTER (WHERE bs.category = 'ast')   AS ast,
    MAX(bs.value) FILTER (WHERE bs.category = 'reb')   AS reb,
    MAX(bs.value) FILTER (WHERE bs.category = 'tov')   AS tov,
    MAX(bs.value) FILTER (WHERE bs.category = 'fgm')   AS fgm,
    MAX(bs.value) FILTER (WHERE bs.category = 'fga')   AS fga,
    MAX(bs.value) FILTER (WHERE bs.category = 'ftm')   AS ftm,
    MAX(bs.value) FILTER (WHERE bs.category = 'fta')   AS fta,
    MAX(bs.value) FILTER (WHERE bs.category = 'fg3_m') AS fg3_m,
    COALESCE(
        MAX(bs.value) FILTER (WHERE bs.category = 'fgm')
        / NULLIF(MAX(bs.value) FILTER (WHERE bs.category = 'fga'), 0),
        0
    ) AS fg_pct,
    COALESCE(
        MAX(bs.value) FILTER (WHERE bs.category = 'ftm')
        / NULLIF(MAX(bs.value) FILTER (WHERE bs.category = 'fta'), 0),
        0
    ) AS ft_pct,
    MAX(bs.value) FILTER (WHERE bs.category = 'dd2')   AS dd2,
    MAX(bs.value) FILTER (WHERE bs.category = 'td3')   AS td3,
    lc.competitor_abbrev,
    lc.competitor_name
FROM fty.matchup_box_score bs
    LEFT JOIN fty.league_competitor lc
        ON bs.season = lc.season
       AND bs.platform = lc.platform
       AND bs.league_id = lc.league_id
       AND bs.competitor_id = lc.competitor_id
GROUP BY bs.season, bs.platform, bs.league_id, bs.competitor_id, bs.matchup,
         lc.competitor_abbrev, lc.competitor_name
