-- util.update_schedule drives __main__.py. Each row is one table update, and its
-- `cadence` names the cron.sh argument that runs it: `./cron.sh daily` selects every
-- unpaused row with cadence = 'daily', while a bare `./cron.sh` runs every unpaused row
-- regardless of cadence.
--
-- job_family groups rows by the kind of thing they maintain, so a runner can be pointed at
-- one family of jobs instead of a whole schema. __main__.py hardcodes job_family = 'database';
-- every row is currently 'database'. Nullable until a second family is in use.
--
-- Run order: __main__.py orders by schema_sequence, then function_sequence, then
-- table_name (NULLS LAST on the two sequence keys). schema_sequence is the rank shared by
-- every row of a `schema`, chosen to keep the dependency order nba -> statyx -> fty ->
-- util (nba box scores feed fty's matchup box score); ordering by the `schema` text would
-- put fty first and break that. function_sequence orders the functions within a schema;
-- NULL sorts last. `pause` excludes a row from every run, including a bare `./cron.sh`.
--
-- Hand-applied, like sql/views and sql/functions: the database is the system of record
-- and this file is the mirror. Run it against POSTGRES.
--
-- CockroachDB needs the same rewrite issued by hand -- the postgres -> Cockroach transport
-- does NOT carry a column order change: transport_from deletes the rows it read and appends
-- them again (TRANSPORT_STRATEGY = "full" for this table), so the target table keeps whatever
-- shape it already has. The Cockroach form is below, commented out; it differs because
-- Cockroach rejects DDL inside an explicit transaction (run the statements one at a time),
-- a schema_locked table rejects DDL until it is unlocked, and a recreated table carries no
-- GRANTs, so the read role has to be granted again.
--
-- Why a rebuild and not ADD COLUMN: neither Postgres nor CockroachDB can place a column at
-- a position; ADD COLUMN only appends. The live column order (job_family, schema, table_name,
-- associated_function, cadence, schema_sequence, function_sequence, pause) is set here, so
-- a bare `SELECT *` reads in the order __main__.py cares about.
--
-- The column is `job_family` and not `family` because CockroachDB reserves FAMILY (column
-- families): the column would have to be quoted in every hand-written statement there, and
-- SQLAlchemy's Cockroach dialect does not quote it, so polars/pandas writes -- including
-- transport_from -- fail with `at or near "family": syntax error`.

BEGIN;
ALTER TABLE util.update_schedule RENAME TO update_schedule_old;
CREATE TABLE util.update_schedule (
    job_family          VARCHAR,
    schema              VARCHAR,
    table_name          VARCHAR,
    associated_function VARCHAR,
    cadence             VARCHAR,
    schema_sequence     INTEGER,
    function_sequence   INTEGER,
    pause               BOOLEAN
);
INSERT INTO util.update_schedule
    (job_family, schema, table_name, associated_function, cadence, schema_sequence, function_sequence, pause)
SELECT 'database', schema, table_name, associated_function, cadence, schema_sequence, function_sequence, pause
FROM util.update_schedule_old;
DROP TABLE util.update_schedule_old;
COMMIT;

-- CockroachDB, one statement at a time (replaces the table, so re-grant the read role):
--
-- ALTER TABLE util.update_schedule SET (schema_locked = false);
-- ALTER TABLE util.update_schedule RENAME TO update_schedule_old;
-- CREATE TABLE util.update_schedule (
--     job_family          STRING NULL,
--     schema              STRING NULL,
--     table_name          STRING NULL,
--     associated_function STRING NULL,
--     cadence             STRING NULL,
--     schema_sequence     INT8 NULL,
--     function_sequence   INT8 NULL,
--     pause               BOOL NULL,
--     rowid               INT8 NOT VISIBLE NOT NULL DEFAULT unique_rowid(),
--     CONSTRAINT update_schedule_pkey PRIMARY KEY (rowid ASC)
-- ) WITH (schema_locked = true);
-- INSERT INTO util.update_schedule
--     (job_family, schema, table_name, associated_function, cadence, schema_sequence, function_sequence, pause)
-- SELECT 'database', schema, table_name, associated_function, cadence, schema_sequence, function_sequence, pause
-- FROM util.update_schedule_old;
-- DROP TABLE util.update_schedule_old;
-- GRANT SELECT ON TABLE util.update_schedule TO kobe_public;

-- Backfill, e.g.:
-- UPDATE util.update_schedule SET job_family = 'database';
-- UPDATE util.update_schedule SET schema_sequence = 1 WHERE schema = 'nba';
-- UPDATE util.update_schedule SET schema_sequence = 2 WHERE schema = 'statyx';
-- UPDATE util.update_schedule SET schema_sequence = 3 WHERE schema = 'fty';
-- UPDATE util.update_schedule SET schema_sequence = 4 WHERE schema = 'util';
-- UPDATE util.update_schedule SET cadence = 'daily';
-- UPDATE util.update_schedule SET cadence = 'intraday' WHERE table_name = 'nba_injuries';
-- UPDATE util.update_schedule SET function_sequence = 1 WHERE associated_function = 'nba.get_game_schedule';

-- Optional, once no row is left unassigned:
-- ALTER TABLE util.update_schedule ALTER COLUMN job_family SET NOT NULL;
-- ALTER TABLE util.update_schedule ALTER COLUMN cadence SET NOT NULL;
-- ALTER TABLE util.update_schedule ALTER COLUMN schema_sequence SET NOT NULL;
