-- util.update_schedule drives __main__.py. Each row is one table update, and its
-- `cadence` names the cron.sh argument that runs it: `./cron.sh daily` selects every
-- unpaused row with cadence = 'daily', while a bare `./cron.sh` runs every unpaused row
-- regardless of cadence.
--
-- Run order: __main__.py orders by schema_sequence, then function_sequence, then
-- table_name (NULLS LAST on the two sequence keys). schema_sequence is the rank shared by
-- every row of a `schema`, chosen to keep the dependency order nba -> statyx -> fty ->
-- util (nba box scores feed fty's matchup box score); ordering by the `schema` text would
-- put fty first and break that. function_sequence orders the functions within a schema;
-- NULL sorts last. `pause` excludes a row from every run, including a bare `./cron.sh`.
--
-- Hand-applied, like sql/views and sql/functions: the database is the system of record
-- and this file is the mirror. Run it against POSTGRES only -- CockroachDB is overwritten
-- from postgres afterwards, which recreates the table in this same column order (and then
-- re-appends its implicit rowid).
--
-- Why a rebuild and not ADD COLUMN: neither Postgres nor CockroachDB can place a column at
-- a position; ADD COLUMN only appends. The live column order (schema, table_name,
-- associated_function, cadence, schema_sequence, function_sequence, pause) is set here, so
-- a bare `SELECT *` reads in the order __main__.py cares about.

BEGIN;
ALTER TABLE util.update_schedule RENAME TO update_schedule_old;
CREATE TABLE util.update_schedule (
    schema              VARCHAR,
    table_name          VARCHAR,
    associated_function VARCHAR,
    cadence             VARCHAR,
    schema_sequence     INTEGER,
    function_sequence   INTEGER,
    pause               BOOLEAN
);
INSERT INTO util.update_schedule
    (schema, table_name, associated_function, cadence, schema_sequence, function_sequence, pause)
SELECT schema, table_name, associated_function, cadence, schema_sequence, function_sequence, pause
FROM util.update_schedule_old;
DROP TABLE util.update_schedule_old;
COMMIT;

-- Backfill, e.g.:
-- UPDATE util.update_schedule SET schema_sequence = 1 WHERE schema = 'nba';
-- UPDATE util.update_schedule SET schema_sequence = 2 WHERE schema = 'statyx';
-- UPDATE util.update_schedule SET schema_sequence = 3 WHERE schema = 'fty';
-- UPDATE util.update_schedule SET schema_sequence = 4 WHERE schema = 'util';
-- UPDATE util.update_schedule SET cadence = 'daily';
-- UPDATE util.update_schedule SET cadence = 'intraday' WHERE table_name = 'nba_injuries';
-- UPDATE util.update_schedule SET function_sequence = 1 WHERE associated_function = 'nba.get_game_schedule';

-- Optional, once no row is left unassigned:
-- ALTER TABLE util.update_schedule ALTER COLUMN cadence SET NOT NULL;
-- ALTER TABLE util.update_schedule ALTER COLUMN schema_sequence SET NOT NULL;
