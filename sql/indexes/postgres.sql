-- Primary keys and indexes for the Jetson Postgres database.
--
-- Designed fresh rather than copied from CockroachDB: almost everything there
-- is the implicit rowid primary key, which carries no information.
--
-- Apply once, after the seed, then ANALYZE. Hand-applied like the rest of
-- sql/: the database is the system of record and this file is the mirror.
--
-- Requires PostgreSQL 15 or newer: several keys use NULLS NOT DISTINCT because
-- the natural key contains an optional column (a roster entry date, an activity
-- player, transaction notes) and NULLs must still collide.
--
-- Uniqueness was checked against the 2026-11-13 Mac snapshot. The only cleaning
-- needed is statyx.schedule's 10 exact duplicate rows, which the dedupe below
-- handles; see docs/JETSON_MIGRATION.md.

BEGIN;

-- Reset --------------------------------------------------------------------
-- A seed restored with pg_dump carries whatever keys the source had, names and
-- all. Drop them first so the design below is the only one. Destructive by
-- design: never run this against Cockroach.

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.conrelid::regclass AS tbl, c.conname
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE c.contype IN ('p', 'u', 'f')
          AND n.nspname IN ('nba', 'statyx', 'fty', 'util', 'mod')
        ORDER BY CASE c.contype WHEN 'f' THEN 0 ELSE 1 END
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
    END LOOP;

    FOR r IN
        SELECT schemaname, indexname
        FROM pg_indexes
        WHERE schemaname IN ('nba', 'statyx', 'fty', 'util', 'mod')
    LOOP
        EXECUTE format('DROP INDEX %I.%I', r.schemaname, r.indexname);
    END LOOP;
END $$;

-- nba ----------------------------------------------------------------------

ALTER TABLE nba.teams ADD PRIMARY KEY (team_id);
CREATE UNIQUE INDEX teams_slug_key ON nba.teams (team_slug);

-- Two rows per game, one per team, so game_id alone is not unique. The
-- season/date index is what the dashboard build and the views filter on.
ALTER TABLE nba.league_game_schedule ADD PRIMARY KEY (game_id, team);
CREATE INDEX league_game_schedule_season_date_ix
    ON nba.league_game_schedule (season, game_date);

-- Game-first key serves the box score views; the player index serves every
-- trailing-window feature query in the model repos.
ALTER TABLE nba.player_box_score ADD PRIMARY KEY (game_id, player_id);
CREATE INDEX player_box_score_player_ix
    ON nba.player_box_score (player_id, game_id);

ALTER TABLE nba.team_box_score ADD PRIMARY KEY (game_id, team_id);

-- action_number repeats within a game; action_id is the stable identifier.
ALTER TABLE nba.play_by_play ADD PRIMARY KEY (game_id, action_id);
CREATE INDEX play_by_play_person_ix ON nba.play_by_play (person_id, game_id);

-- game_id is null for games that have not been played yet, so it cannot be part
-- of the key. date/team/player/status is unique on the current data; a duplicate
-- report with a different reason will fail the write rather than duplicate.
ALTER TABLE nba.injuries
    ADD PRIMARY KEY (game_date, team_slug, player_name, status);
CREATE INDEX injuries_player_ix ON nba.injuries (nba_id, game_date);

ALTER TABLE nba.player_info ADD PRIMARY KEY (season, player_id);
ALTER TABLE nba.player_season_stats ADD PRIMARY KEY (season, player_id);

-- entry_date is null for most current roster rows, so a unique index rather than
-- a primary key. The full key is unique; the shorter (season, team, player) is
-- not, because a player can have two stints with the same team.
CREATE UNIQUE INDEX team_roster_key
    ON nba.team_roster (season, team_id, player_id, entry_date)
    NULLS NOT DISTINCT;
CREATE INDEX team_roster_player_ix ON nba.team_roster (player_id, season);

ALTER TABLE nba.key_dates ADD PRIMARY KEY (season, season_type, begin_date);
ALTER TABLE nba.injury_reason_map ADD PRIMARY KEY (reason);

-- Append-only log: the natural key is unique today, but notes is optional, so
-- enforce it as a unique index and leave the column nullable.
CREATE UNIQUE INDEX transaction_log_key
    ON nba.transaction_log (date, transaction_type, team, player, acc_req, notes)
    NULLS NOT DISTINCT;
CREATE INDEX transaction_log_date_ix ON nba.transaction_log (date);

-- statyx -------------------------------------------------------------------

ALTER TABLE statyx.advanced_stats ADD PRIMARY KEY (game_id, player_id, period);
CREATE INDEX advanced_stats_player_ix
    ON statyx.advanced_stats (player_id, game_date);

ALTER TABLE statyx.assist_profile ADD PRIMARY KEY (season, player_id);
ALTER TABLE statyx.contracts ADD PRIMARY KEY (season, team_id, player_id);
ALTER TABLE statyx.defense_vs_position
    ADD PRIMARY KEY (season, updated_at, team, pos);
ALTER TABLE statyx.drives ADD PRIMARY KEY (season, season_type, player_id);

ALTER TABLE statyx.game_stats ADD PRIMARY KEY (game_id, player_id);
CREATE INDEX game_stats_player_ix ON statyx.game_stats (player_id, game_date);

-- sportsbook is null on every row in the snapshot and cannot be part of a key.
ALTER TABLE statyx.matchup_history
    ADD PRIMARY KEY (player_id, game_date, season, opponent_team_id);

ALTER TABLE statyx.play_type_defense
    ADD PRIMARY KEY (season, season_type, team_id, play_type);
ALTER TABLE statyx.play_types ADD PRIMARY KEY (season, player_id);
ALTER TABLE statyx.player_info ADD PRIMARY KEY (season, player_id);

ALTER TABLE statyx.potential_assists
    ADD PRIMARY KEY (season, season_type, game_date, player_id);
CREATE INDEX potential_assists_player_ix
    ON statyx.potential_assists (player_id, game_date);

-- Dedupe first: the Mac snapshot carries 10 exact duplicate rows. Keep one row
-- per (season, game_id) so the key below can be created.
DELETE FROM statyx.schedule a
USING statyx.schedule b
WHERE a.ctid < b.ctid
  AND a.season = b.season
  AND a.game_id = b.game_id;

ALTER TABLE statyx.schedule ADD PRIMARY KEY (season, game_id);

ALTER TABLE statyx.scoring_breakdown
    ADD PRIMARY KEY (season, season_type, player_id);
ALTER TABLE statyx.shooting_splits
    ADD PRIMARY KEY (season, season_type, player_id);
ALTER TABLE statyx.shot_zone_defense
    ADD PRIMARY KEY (season, season_type, team_id, last_n_games);
ALTER TABLE statyx.shot_zones
    ADD PRIMARY KEY (season, season_type, team_id, player_id, last_n_games);
ALTER TABLE statyx.standings ADD PRIMARY KEY (season, date, team_id);
ALTER TABLE statyx.team_assist_defense
    ADD PRIMARY KEY (season, season_type, team_id);

CREATE UNIQUE INDEX team_roster_key
    ON statyx.team_roster (season, team_id, player_id, entry_date)
    NULLS NOT DISTINCT;

-- usage_shock is a computed snapshot with legitimate near-duplicates; no key.

-- fty ----------------------------------------------------------------------

ALTER TABLE fty.category_label ADD PRIMARY KEY (nba_category);

ALTER TABLE fty.competitor_roster
    ADD PRIMARY KEY (season, platform, league_id, timestamp, competitor_id, player_fantasy_id);
CREATE INDEX competitor_roster_competitor_ix
    ON fty.competitor_roster (competitor_id, season, platform, league_id);

ALTER TABLE fty.customer ADD PRIMARY KEY (customer_id);
-- The entry app looks the customer up by lower(email).
CREATE UNIQUE INDEX customer_email_key ON fty.customer (lower(email));

ALTER TABLE fty.customer_league
    ADD PRIMARY KEY (customer_id, season, platform, league_id);
CREATE INDEX customer_league_registry_ix
    ON fty.customer_league (season, platform, league_id);

ALTER TABLE fty.customer_platform ADD PRIMARY KEY (customer_id, platform);

ALTER TABLE fty.free_agents
    ADD PRIMARY KEY (season, platform, league_id, timestamp, player_id);

ALTER TABLE fty.league ADD PRIMARY KEY (season, platform, league_id);

ALTER TABLE fty.league_byes
    ADD PRIMARY KEY (season, platform, league_id, matchup_period, competitor_id);
ALTER TABLE fty.league_categories
    ADD PRIMARY KEY (season, platform, league_id, category);
ALTER TABLE fty.league_competitor
    ADD PRIMARY KEY (season, platform, league_id, competitor_id);
ALTER TABLE fty.league_matchup
    ADD PRIMARY KEY (season, platform, league_id, matchup_period, competitor_id);
ALTER TABLE fty.league_matchup_dates
    ADD PRIMARY KEY (season, platform, league_id, matchup_period);

ALTER TABLE fty.matchup_box_score
    ADD PRIMARY KEY (season, platform, league_id, matchup, competitor_id, category);
ALTER TABLE fty.matchup_result
    ADD PRIMARY KEY (season, platform, league_id, matchup, competitor_id);

ALTER TABLE fty.platform_category ADD PRIMARY KEY (platform, platform_category);
CREATE UNIQUE INDEX platform_category_nba_key
    ON fty.platform_category (platform, nba_category);
ALTER TABLE fty.platform_category
    ADD CONSTRAINT platform_category_nba_category_fkey
    FOREIGN KEY (nba_category) REFERENCES fty.category_label (nba_category);

-- player is null on team-level activity rows, so no primary key.
CREATE UNIQUE INDEX recent_activity_key
    ON fty.recent_activity (season, platform, league_id, timestamp, competitor_id, action, player)
    NULLS NOT DISTINCT;

ALTER TABLE fty.scoring_format ADD PRIMARY KEY (platform, scoring_type);

-- util ---------------------------------------------------------------------

ALTER TABLE util.player ADD PRIMARY KEY (player_key);
ALTER TABLE util.player_source_id ADD PRIMARY KEY (platform, source_id);
ALTER TABLE util.player_source_id
    ADD CONSTRAINT player_source_id_player_key_fkey
    FOREIGN KEY (player_key) REFERENCES util.player (player_key);
CREATE INDEX player_source_id_player_ix
    ON util.player_source_id (player_key, platform);

ALTER TABLE util.player_identity_review ADD PRIMARY KEY (review_id);
CREATE UNIQUE INDEX player_identity_review_input_key
    ON util.player_identity_review (input_hash);
CREATE INDEX player_identity_review_status_ix
    ON util.player_identity_review (status);

ALTER TABLE util.table_column_order
    ADD PRIMARY KEY (schema, table_name, column_name);

-- associated_function is the natural identity; table_name is null for
-- util.sync_player_identity.
ALTER TABLE util.update_schedule
    ADD PRIMARY KEY (job_family, associated_function);

-- update_log is append-only with no natural key. The task_time index serves
-- util.last_update_vw's ORDER BY ... LIMIT 1.
CREATE INDEX update_log_task_time_ix ON util.update_log (task_time DESC);

-- The draft app appends and deletes by league; repeats are legitimate (a player
-- can be drafted, dropped and drafted again), so no unique key.
CREATE INDEX draft_player_log_league_ix ON util.draft_player_log (league_id);

-- mod ----------------------------------------------------------------------

ALTER TABLE mod.injury_daily_forecast_base
    ADD PRIMARY KEY (prediction_date, spell_id);

ALTER TABLE mod.player_archetype_base ADD PRIMARY KEY (game_id, player_id);
CREATE INDEX player_archetype_base_player_date_ix
    ON mod.player_archetype_base (player_id, game_date);
CREATE INDEX player_archetype_base_season_ix
    ON mod.player_archetype_base (season, game_id, player_id);

ALTER TABLE mod.player_archetype_current_base ADD PRIMARY KEY (player_id);
ALTER TABLE mod.player_archetype_model_base ADD PRIMARY KEY (model_cutoff);
ALTER TABLE mod.player_archetype_profile_base ADD PRIMARY KEY (archetype_label);

ALTER TABLE mod.team_hierarchy_base
    ADD PRIMARY KEY (game_date, game_id, team_id, player_id);

COMMIT;
