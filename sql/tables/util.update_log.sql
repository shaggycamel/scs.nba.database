-- util.update_log records one row per object update plus 'process start'/'process end',
-- written by __main__.py's log_event(). `cadence` mirrors the cron.sh argument for the
-- run ('all' for a bare run), the same value that selected rows in util.update_schedule.
--
-- Hand-applied, like sql/views and sql/functions: the database is the system of record
-- and this file is the mirror. Run it against POSTGRES only -- CockroachDB is overwritten
-- from postgres afterwards, which recreates the table in this same column order (and then
-- re-appends its implicit rowid).
--
-- Why a rebuild and not ADD COLUMN: neither Postgres nor CockroachDB can place a column at
-- a position; ADD COLUMN only appends. Pre-existing rows get cadence = NULL, because they
-- predate the feature and were not selected by a cadence filter.

BEGIN;
ALTER TABLE util.update_log RENAME TO update_log_old;
CREATE TABLE util.update_log (
    table_name     TEXT,
    process_date   TIMESTAMPTZ,
    cadence        TEXT,
    successful_run BOOLEAN,
    error_message  TEXT
);
INSERT INTO util.update_log (table_name, process_date, cadence, successful_run, error_message)
SELECT table_name, process_date, NULL, successful_run, error_message FROM util.update_log_old;
DROP TABLE util.update_log_old;
COMMIT;
