CREATE OR REPLACE VIEW nba.play_by_play_vw AS

 SELECT lgs.season,
    lgs.season_type,
    lgs.game_date,
    pbp.game_id,
    pbp.action_number,
    pbp.action_id,
    pbp.period,
    pbp.clock,
    pbp.team_id,
    pbp.team_tricode,
    pbp.person_id,
    nm.conformed_name::TEXT AS player_name,
    pbp.player_name AS raw_name,
    pbp.player_name_i,
    pbp.action_type,
    pbp.sub_type,
    pbp.description,
    pbp.is_field_goal,
    pbp.shot_result,
    pbp.shot_distance,
    pbp.shot_value,
    pbp.court_x,
    pbp.court_y,
    pbp.score_home,
    pbp.score_away,
    pbp.points_total,
    pbp.location,
    pbp.video_available
   FROM nba.play_by_play pbp
     LEFT JOIN ( SELECT g.game_id,
            max(g.season) AS season,
            max(g.season_type) AS season_type,
            max(g.game_date) AS game_date
           FROM nba.league_game_schedule g
          GROUP BY g.game_id) lgs ON pbp.game_id::DOUBLE PRECISION = lgs.game_id::DOUBLE PRECISION
     LEFT JOIN util.player_id_map_vw nm ON pbp.person_id::DOUBLE PRECISION = nm.nba_id::DOUBLE PRECISION;
