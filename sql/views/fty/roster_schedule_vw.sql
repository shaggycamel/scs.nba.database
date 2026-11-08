CREATE OR REPLACE VIEW fty.roster_schedule_vw AS

-- Player identity comes from fty.player_vw, which resolves the fantasy id to the
-- canonical nba player_id and conformed name (replacing util.conformed_player_id_RETIRED).
-- player_vw emits lower case platform, hence lower(roster.platform).

SELECT
    roster.season,
    roster.platform,
    roster.league_id,
    roster.assigned_date,
    roster.matchup_period,
    schedule_dates.matchup_start,
    schedule_dates.matchup_end,
    roster.competitor_id,
    competitor.competitor_name,
    roster.player_fantasy_id,
    plyr.player_id,
    plyr.player_name,
    roster.player_team,
    roster.player_injury_status,
    roster.player_acquisition_type,
    schedule.opponent_id::BIGINT AS opponent_id,
    opponent.competitor_name     AS opponent_name,
    competitor.division_id,
    competitor.division_name,
    roster.lineup_slot
FROM fty.competitor_roster roster
    LEFT JOIN fty.league_matchup schedule
        ON roster.season = schedule.season
       AND roster.platform = schedule.platform
       AND roster.league_id = schedule.league_id
       AND roster.competitor_id = schedule.competitor_id
       AND roster.matchup_period = schedule.matchup_period
    LEFT JOIN fty.league_matchup_dates schedule_dates
        ON roster.season = schedule_dates.season
       AND roster.platform = schedule_dates.platform
       AND roster.league_id = schedule_dates.league_id
       AND roster.matchup_period = schedule_dates.matchup_period
    LEFT JOIN fty.league_competitor competitor
        ON roster.season = competitor.season
       AND roster.platform = competitor.platform
       AND roster.league_id = competitor.league_id
       AND roster.competitor_id = competitor.competitor_id
    LEFT JOIN fty.league_competitor opponent
        ON roster.season = opponent.season
       AND roster.platform = opponent.platform
       AND roster.league_id = opponent.league_id
       AND schedule.opponent_id = opponent.competitor_id::DOUBLE PRECISION
    LEFT JOIN fty.player_vw plyr
        ON plyr.platform = LOWER(roster.platform)
       AND plyr.fantasy_id = roster.player_fantasy_id
