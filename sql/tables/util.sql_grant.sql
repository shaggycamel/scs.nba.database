-- util.sql_grant is the hand-maintained allowlist of SQL users and the SELECT /
-- INSERT / DELETE privileges they are meant to hold on the data schemas. One row
-- per grant: grantee x schema x relation x privilege. Absence of a row means no
-- grant is intended.
--
-- This is the intended access contract, not a live snapshot. kobe_public reads
-- views, plus the draft app's log table:
--   * 58 views across nba, statyx, fty, util and mod;
--   * util.draft_player_log, with SELECT, INSERT and DELETE, because the draft
--     app reads, adds and removes picks. It is the only base table in the
--     contract.
--
-- The statyx views are pass-throughs. They exist so read-only consumers can
-- reach the Statyx-sourced tables at all: kobe_public has USAGE on the schema
-- but no SELECT on any statyx base table.
--
-- Database.apply_sql_grant() reads this table and grants each row; keep it
-- complete when views or the contract change. ai_tools and its 10 raw nba
-- SELECT grants were removed on 2026-11-13; util.conformed_player_id was
-- retired and dropped on 2026-11-13.
--
-- Owner only: do not GRANT SELECT on this table to kobe_public.
-- apply_sql_grant() runs as the owning role (jetson-write on the Jetson, which
-- holds the system of record), so the owner already has access.
--
-- The table exists on the Jetson and on CockroachDB. Local Postgres has no
-- kobe_public, so it is not applied there; the Postgres form is at the bottom
-- for reference.
--
-- Re-running this file re-seeds the rows (DELETE then INSERT), so it is safe to
-- apply repeatedly. A column change needs a rebuild, like the other tables in
-- this directory: neither dialect can place a column at a position. Unlock the
-- table first with ALTER TABLE util.sql_grant SET (schema_locked = false).
--
-- Hand-applied: the database is the system of record and this file is the
-- mirror. Run each statement on its own -- CockroachDB rejects DDL inside an
-- explicit transaction.

CREATE TABLE IF NOT EXISTS util.sql_grant (
    grantee       STRING NOT NULL,
    schema        STRING NOT NULL,
    table_name    STRING NOT NULL,
    relation_type STRING NOT NULL,
    privilege     STRING NOT NULL,
    CONSTRAINT sql_grant_pkey PRIMARY KEY (grantee, schema, table_name, privilege),
    CONSTRAINT sql_grant_relation_type_check CHECK (relation_type IN ('table', 'view')),
    CONSTRAINT sql_grant_privilege_check CHECK (privilege IN ('SELECT', 'INSERT', 'DELETE'))
) WITH (schema_locked = true);

-- DML transaction: DDL above stays outside it.
BEGIN;
DELETE FROM util.sql_grant;
INSERT INTO util.sql_grant
    (grantee, schema, table_name, relation_type, privilege)
VALUES
('kobe_public', 'nba', 'daily_standings_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'injuries_parsed_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'injuries_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'key_dates_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'league_game_schedule_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'play_by_play_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'player_box_score_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'player_info_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'season_segments_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'team_box_score_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'team_roster_vw', 'view', 'SELECT'),
('kobe_public', 'nba', 'teams_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'advanced_stats_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'assist_profile_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'contracts_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'defense_vs_position_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'drives_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'game_stats_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'matchup_history_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'play_type_defense_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'play_types_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'player_info_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'potential_assists_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'schedule_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'scoring_breakdown_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'shooting_splits_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'shot_zone_defense_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'shot_zones_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'standings_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'team_assist_defense_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'team_roster_vw', 'view', 'SELECT'),
('kobe_public', 'statyx', 'usage_shock_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'base_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'categories_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'category_label_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'customer_league_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'customer_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'free_agents_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'league_competitor_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'league_schedule_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'league_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'matchup_box_score_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'matchup_result_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'player_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'recent_activity_vw', 'view', 'SELECT'),
('kobe_public', 'fty', 'roster_schedule_vw', 'view', 'SELECT'),
('kobe_public', 'util', 'active_player_vw', 'view', 'SELECT'),
('kobe_public', 'util', 'last_update_vw', 'view', 'SELECT'),
('kobe_public', 'util', 'player_directory_vw', 'view', 'SELECT'),
('kobe_public', 'util', 'player_id_map_vw', 'view', 'SELECT'),
('kobe_public', 'util', 'unmatched_player_source_vw', 'view', 'SELECT'),
('kobe_public', 'util', 'draft_player_log', 'table', 'DELETE'),
('kobe_public', 'util', 'draft_player_log', 'table', 'INSERT'),
('kobe_public', 'util', 'draft_player_log', 'table', 'SELECT'),
('kobe_public', 'mod', 'game_day_vw', 'view', 'SELECT'),
('kobe_public', 'mod', 'injury_daily_forecast_vw', 'view', 'SELECT'),
('kobe_public', 'mod', 'player_archetype_vw', 'view', 'SELECT'),
('kobe_public', 'mod', 'player_stat_forecast_vw', 'view', 'SELECT'),
('kobe_public', 'mod', 'team_hierarchy_vw', 'view', 'SELECT');
COMMIT;

-- Verify after seeding. Expect: DELETE util table 1; INSERT util table 1;
-- SELECT fty view 14; SELECT mod view 5; SELECT nba view 12; SELECT statyx
-- view 20; SELECT util table 1; SELECT util view 5.
--
-- SELECT privilege, schema, relation_type, count(*) AS n
-- FROM util.sql_grant
-- GROUP BY 1, 2, 3
-- ORDER BY 1, 2, 3;

-- Postgres form, reference only (do not run: local Postgres has no kobe_public).
-- The seed above is identical; only the types and the schema_locked clause differ.
--
-- BEGIN;
-- CREATE TABLE IF NOT EXISTS util.sql_grant (
--     grantee       VARCHAR NOT NULL,
--     schema        VARCHAR NOT NULL,
--     table_name    VARCHAR NOT NULL,
--     relation_type VARCHAR NOT NULL,
--     privilege     VARCHAR NOT NULL,
--     CONSTRAINT sql_grant_pkey PRIMARY KEY (grantee, schema, table_name, privilege),
--     CONSTRAINT sql_grant_relation_type_check CHECK (relation_type IN ('table', 'view')),
--     CONSTRAINT sql_grant_privilege_check CHECK (privilege IN ('SELECT', 'INSERT', 'DELETE'))
-- );
-- DELETE FROM util.sql_grant;
-- INSERT INTO util.sql_grant
--     (grantee, schema, table_name, relation_type, privilege)
-- VALUES
--     ...same rows as above...
-- COMMIT;
