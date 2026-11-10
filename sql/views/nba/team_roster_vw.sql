CREATE OR REPLACE VIEW nba.team_roster_vw AS

-- Player naming and cross platform ids come from util.player_id_map_vw, replacing
-- util.conformed_player_id_RETIRED. nba.team_roster.player_id is double precision,
-- hence the cast on the join.

SELECT tr.season,
    tr.team_id,
    tr.team_slug,
    tr.player_id,
    nm.espn_id,
    nm.yahoo_id,
    nm.conformed_name AS player_name,
    tr.player::VARCHAR AS raw_name,
    tr."position",
    tr.how_acquired,
    COALESCE(ct.base_salary, tr.salary) AS salary,
    COALESCE(tr.entry_date, kd.begin_date) AS entry_date,
    COALESCE(tr.exit_date, kd.end_date) AS exit_date
   FROM nba.team_roster tr
     LEFT JOIN util.player_id_map_vw nm ON tr.player_id = nm.nba_id::DOUBLE PRECISION
     LEFT JOIN statyx.contracts ct ON ct.player_id = nm.statyx_id::BIGINT AND ct.season = tr.season
     LEFT JOIN ( SELECT league_game_schedule.season,
            MIN(league_game_schedule.game_date) AS begin_date,
            MAX(league_game_schedule.game_date) + 1 AS end_date
           FROM nba.league_game_schedule
          WHERE league_game_schedule.season_type = 'Regular Season'::TEXT
          GROUP BY league_game_schedule.season) kd ON tr.season = kd.season
