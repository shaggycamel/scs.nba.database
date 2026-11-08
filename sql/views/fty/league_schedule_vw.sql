CREATE OR REPLACE VIEW fty.league_schedule_vw AS

-- league_matchup.opponent_id is double precision in fty; cast to bigint so consumers
-- join cleanly against competitor_id (fty's view cast the other direction instead).
--
-- A bye has two representations in the source data, and is_bye normalises both:
--   2024-25 - a league_matchup row exists with opponent_id null
--   2025-26 - no league_matchup row at all; the fact lives only in league_byes, so those
--             competitors have to be unioned back in or they vanish from the schedule

SELECT
    mup_dates.season,
    mup_dates.platform,
    mup_dates.league_id,
    mup_dates.matchup_period,
    mup_dates.matchup_start,
    mup_dates.matchup_end,
    mup.competitor_id,
    mup.opponent_id::BIGINT AS opponent_id,
    mup.competitor_id IS NOT NULL AND mup.opponent_id IS NULL AS is_bye
FROM fty.league_matchup_dates mup_dates
    LEFT JOIN fty.league_matchup mup
        ON mup_dates.season = mup.season
       AND mup_dates.platform = mup.platform
       AND mup_dates.league_id = mup.league_id
       AND mup_dates.matchup_period = mup.matchup_period

UNION ALL

SELECT
    mup_dates.season,
    mup_dates.platform,
    mup_dates.league_id,
    mup_dates.matchup_period,
    mup_dates.matchup_start,
    mup_dates.matchup_end,
    bye.competitor_id,
    NULL::BIGINT AS opponent_id,
    TRUE AS is_bye
FROM fty.league_byes bye
    JOIN fty.league_matchup_dates mup_dates
        ON mup_dates.season = bye.season::TEXT
       AND mup_dates.platform = bye.platform::TEXT
       AND mup_dates.league_id = bye.league_id
       AND mup_dates.matchup_period = bye.matchup_period
