-- Column ordering for fty.competitor_roster, the one table written through
-- scs_hub's write_ordered(). conform() renames by origin_name and then selects
-- exactly these columns, so a column missing from this registration is silently
-- dropped from the insert rather than raising. Keep the list in step with
-- EspnNbaHandler.get_competitor_roster().
--
-- origin_name is NULL throughout: the handler builds the frame with the final
-- column names, so there is nothing to rename. Hand-applied like the rest of
-- sql/tables; the database is the system of record and this file is the mirror.

BEGIN;

DELETE FROM util.table_column_order
WHERE schema = 'fty' AND table_name = 'competitor_roster';

INSERT INTO util.table_column_order
(schema, table_name, column_name, origin_name, column_order)
VALUES
('fty', 'competitor_roster', 'season',                  NULL,  1),
('fty', 'competitor_roster', 'platform',                NULL,  2),
('fty', 'competitor_roster', 'league_id',               NULL,  3),
('fty', 'competitor_roster', 'timestamp',               NULL,  4),
('fty', 'competitor_roster', 'assigned_date',           NULL,  5),
('fty', 'competitor_roster', 'matchup_period',          NULL,  6),
('fty', 'competitor_roster', 'competitor_id',           NULL,  7),
('fty', 'competitor_roster', 'player_fantasy_id',       NULL,  8),
('fty', 'competitor_roster', 'player_name',             NULL,  9),
('fty', 'competitor_roster', 'player_team',             NULL, 10),
('fty', 'competitor_roster', 'player_injury_status',    NULL, 11),
('fty', 'competitor_roster', 'player_acquisition_type', NULL, 12),
('fty', 'competitor_roster', 'lineup_slot',             NULL, 13);

COMMIT;
