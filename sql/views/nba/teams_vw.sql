CREATE OR REPLACE VIEW nba.teams_vw AS

 SELECT teams.team_id,
    teams.team_slug,
    teams.team_long,
    teams.team_name,
    teams.conference,
    teams.division,
    teams.first_season,
    teams.last_season,
    teams.stadium,
    teams.stadium_capacity,
    teams.active
   FROM nba.teams
  WHERE teams.active
