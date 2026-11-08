CREATE OR REPLACE VIEW nba.teams_vw AS

 SELECT teams.team_id,
    teams.team_slug,
    teams.team_long,
    teams.team_name
   FROM nba.teams
  WHERE teams.active
