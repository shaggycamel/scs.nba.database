CREATE OR REPLACE VIEW util.player_id_map_vw AS

-- One row per player, with that player's id and name on each source platform.
-- Replaces util.conformed_player_id_RETIRED, built from util.player + util.player_source_id.
--
-- Some player_keys carry more than one id on a platform (37 on nba, 6 each on espn and
-- statyx) from name collisions, truncated ids and bad merges. One id is chosen per
-- player_key per platform, preferring in order:
--   1. an id that still appears in util.player_directory_vw (ie is live in source data)
--   2. an id whose source name matches the conformed name (catches merges such as the
--      statyx id named 'Armel Traore' sitting under conformed 'Nolan Traore')
--   3. for nba, the id with the most box score rows (the established player)
--   4. the highest id, as a deterministic tie break

WITH dir AS (
    SELECT DISTINCT platform, source_id
    FROM util.player_directory_vw
),

box AS (
    SELECT player_id, COUNT(*) AS box_rows
    FROM nba.player_box_score
    GROUP BY player_id
),

ranked AS (
    SELECT
        psi.player_key,
        psi.platform,
        psi.source_id,
        psi.source_name,
        ROW_NUMBER() OVER (
            PARTITION BY psi.player_key, psi.platform
            ORDER BY
                (dir.source_id IS NOT NULL) DESC,
                (psi.source_name = p.conformed_name) DESC,
                COALESCE(box.box_rows, 0) DESC,
                psi.source_id DESC
        ) AS rn
    FROM util.player_source_id psi
        JOIN util.player p
            ON p.player_key = psi.player_key
        LEFT JOIN dir
            ON dir.platform = psi.platform
           AND dir.source_id = psi.source_id
        LEFT JOIN box
            ON psi.platform = 'nba'
           AND box.player_id = psi.source_id
)

SELECT
    p.player_key,
    p.conformed_name,
    MAX(r.source_id)   FILTER (WHERE r.platform = 'nba')    AS nba_id,
    MAX(r.source_name) FILTER (WHERE r.platform = 'nba')    AS nba_name,
    MAX(r.source_id)   FILTER (WHERE r.platform = 'espn')   AS espn_id,
    MAX(r.source_name) FILTER (WHERE r.platform = 'espn')   AS espn_name,
    MAX(r.source_id)   FILTER (WHERE r.platform = 'yahoo')  AS yahoo_id,
    MAX(r.source_name) FILTER (WHERE r.platform = 'yahoo')  AS yahoo_name,
    MAX(r.source_id)   FILTER (WHERE r.platform = 'statyx') AS statyx_id,
    MAX(r.source_name) FILTER (WHERE r.platform = 'statyx') AS statyx_name
FROM util.player p
    LEFT JOIN ranked r
        ON r.player_key = p.player_key
       AND r.rn = 1
GROUP BY p.player_key, p.conformed_name
