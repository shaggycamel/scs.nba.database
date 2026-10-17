CREATE OR REPLACE VIEW nba.schedule_vw AS
WITH nba_rows AS (
    SELECT
        'nba.league_game_schedule'::text AS source,
        lgs.season_type,
        lgs.season,
        lgs.game_id,
        lgs.game_date,
        lgs.matchup,
        lgs.team,
        lgs.opponent,
        lgs.home,
        lgs.team_winner,
        lgs.team_loser
    FROM nba.league_game_schedule AS lgs
    INNER JOIN (
        SELECT team_slug
        FROM nba.teams
    ) AS relevant_teams
        ON lgs.team = relevant_teams.team_slug
    WHERE lgs.season <= '2025-26'
),
statyx_games AS (
    SELECT
        CASE
            WHEN s.postseason THEN 'Playoffs'
            ELSE 'Regular Season'
        END AS season_type,
        s.season,
        s.game_id,
        s.game_date,
        s.home_team_abbr,
        s.visitor_team_abbr,
        CASE
            WHEN s.status = 'Final'
             AND s.home_team_score > s.visitor_team_score
                THEN s.home_team_abbr
            WHEN s.status = 'Final'
             AND s.visitor_team_score > s.home_team_score
                THEN s.visitor_team_abbr
            ELSE NULL::text
        END AS team_winner,
        CASE
            WHEN s.status = 'Final'
             AND s.home_team_score > s.visitor_team_score
                THEN s.visitor_team_abbr
            WHEN s.status = 'Final'
             AND s.visitor_team_score > s.home_team_score
                THEN s.home_team_abbr
            ELSE NULL::text
        END AS team_loser
    FROM statyx.schedule AS s
    WHERE s.season > '2025-26'
),
statyx_rows AS (
    SELECT
        'statyx.schedule'::text AS source,
        g.season_type,
        g.season,
        g.game_id,
        g.game_date,
        CASE
            WHEN side.is_home
                THEN g.home_team_abbr || ' vs. ' || g.visitor_team_abbr
            ELSE g.visitor_team_abbr || ' @ ' || g.home_team_abbr
        END AS matchup,
        side.team,
        side.opponent,
        side.is_home AS home,
        g.team_winner,
        g.team_loser
    FROM statyx_games AS g
    CROSS JOIN LATERAL (
        VALUES
            (g.home_team_abbr, g.visitor_team_abbr, TRUE),
            (g.visitor_team_abbr, g.home_team_abbr, FALSE)
    ) AS side(team, opponent, is_home)
    INNER JOIN (
        SELECT team_slug
        FROM nba.teams
    ) AS relevant_teams
        ON side.team = relevant_teams.team_slug
)
SELECT
    source,
    season_type,
    season,
    game_id,
    game_date,
    matchup,
    team,
    opponent,
    home,
    team_winner,
    team_loser
FROM nba_rows

UNION ALL

SELECT
    source,
    season_type,
    season,
    game_id,
    game_date,
    matchup,
    team,
    opponent,
    home,
    team_winner,
    team_loser
FROM statyx_rows;
