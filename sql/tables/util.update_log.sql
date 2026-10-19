-- util.update_log records one row per object update plus 'process start'/'process end',
-- written by __main__.py's log_event() here and by the dashboard repo's log_update().
--
--   source         the repo that wrote the row: 'nba_cockroach_db' from here,
--                  'scs.nba.fty.league_dash' from the dashboard
--   job_kickoff    the run's start time, identical on every row of one run, so a run
--                  can be grouped
--   cadence        mirrors the cron.sh argument that selected the run ('all' for a bare
--                  run), the same value that selected rows in util.update_schedule
--   task           the scheduled row's associated_function
--                  ('nba.get_team_injuries', 'process start') from here, or a
--                  'dashboard:*' event name from the dashboard repo
--   task_time      when the row was written
--   success        whether that object's update succeeded
--   error_message  the failure text, NULL on success
--
-- Hand-applied, like sql/views and sql/functions: the database is the system of record
-- and this file is the mirror. Run it against POSTGRES only -- CockroachDB is overwritten
-- from postgres afterwards, which recreates the table in this same column order (and then
-- re-appends its implicit rowid).
--
-- Why a rebuild and not ADD COLUMN: neither Postgres nor CockroachDB can place a column at
-- a position; ADD COLUMN only appends. So this file rebuilds the table whenever the column
-- set or its order changes. The INSERT names all seven columns on both sides, so it carries
-- every value through whatever order the old table had.
--
-- History: table_name -> task, process_date -> task_time, successful_run -> success, plus
-- source / job_kickoff added (rows predating those keep job_kickoff = NULL and cadence =
-- NULL); then the columns were reordered to source, job_kickoff, cadence, task, task_time,
-- success, error_message.

BEGIN;
ALTER TABLE util.update_log RENAME TO update_log_old;
CREATE TABLE util.update_log (
    source         VARCHAR,
    job_kickoff    TIMESTAMPTZ,
    cadence        TEXT,
    task           TEXT,
    task_time      TIMESTAMPTZ,
    success        BOOLEAN,
    error_message  TEXT
);
INSERT INTO util.update_log (source, job_kickoff, cadence, task, task_time, success, error_message)
SELECT source, job_kickoff, cadence, task, task_time, success, error_message FROM util.update_log_old;
DROP TABLE util.update_log_old;
COMMIT;
