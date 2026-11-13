-- The most recent successful update, one row. The full log stays private.
CREATE OR REPLACE VIEW util.last_update_vw AS
SELECT
    source,
    task,
    task_time
FROM util.update_log
WHERE success
ORDER BY task_time DESC
LIMIT 1;
