CREATE OR REPLACE VIEW fty.player_vw AS

-- Resolves a fantasy platform's player id to the canonical nba player id and name.
-- Replaces util.conformed_player_id_RETIRED.
--
-- platform is emitted lower case, as util.player_source_id stores it. Consumers in
-- fty join with lower(x.platform), matching util.player_directory_vw's convention.
--
-- 37 player_keys carry two nba source ids (name collisions and truncated/legacy ids),
-- which would otherwise fan a single roster row out into two. DISTINCT ON keeps the id
-- with the most box score rows, which is the established player in every observed case.

WITH nba_id AS (
    SELECT DISTINCT ON (psi.player_key)
        psi.player_key,
        psi.source_id AS player_id
    FROM util.player_source_id psi
    LEFT JOIN (
        SELECT player_id, COUNT(*) AS box_rows
        FROM nba.player_box_score
        GROUP BY player_id
    ) bx ON bx.player_id = psi.source_id
    WHERE psi.platform = 'nba'
    ORDER BY psi.player_key, COALESCE(bx.box_rows, 0) DESC, psi.source_id
)

SELECT
    src.platform,
    src.source_id AS fantasy_id,
    src.source_name AS fantasy_name,
    src.player_key,
    nba_id.player_id,
    p.conformed_name AS player_name
FROM util.player_source_id src
    LEFT JOIN nba_id ON nba_id.player_key = src.player_key
    LEFT JOIN util.player p ON p.player_key = src.player_key
WHERE src.platform <> 'nba'
