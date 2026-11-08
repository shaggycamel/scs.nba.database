CREATE OR REPLACE VIEW nba.injuries_vw AS

-- Player naming comes from util.player_id_map_vw, replacing util.conformed_player_id_RETIRED.
-- key_dates windows overlap: All Star sits inside the regular season, so the
-- plain join duplicated every report on 2025-02-19. Take the narrowest matching
-- window instead, which is the most specific segment, and exactly one row per
-- report.

SELECT kd.season,
    kd.season_type,
    inj.game_date,
    inj.game_id,
    inj.matchup,
    inj.team,
    inj.team_slug,
    nm.conformed_name AS player_name,
    inj.nba_id,
    inj.status,
    inj.reason,
    tm.team_id
   FROM nba.injuries inj
     LEFT JOIN LATERAL (
         SELECT kd.season, kd.season_type
           FROM nba.key_dates kd
          WHERE inj.game_date >= kd.begin_date AND inj.game_date <= kd.end_date
          ORDER BY (kd.end_date - kd.begin_date), kd.begin_date DESC
          LIMIT 1
     ) kd ON TRUE
     LEFT JOIN util.player_id_map_vw nm ON inj.nba_id = nm.nba_id
     LEFT JOIN nba.teams tm ON inj.team_slug = tm.team_slug
