-- Roster rules, starting-lineup size and division membership, captured from ESPN.
--
-- Hand-applied to POSTGRES and COCKROACHDB, like the other files in this
-- directory: the database is the system of record and this file is the mirror.
-- The columns are nullable so existing rows stay valid until the next fetch.
--
-- `roster_size` is the sum of ESPN's lineupSlotCounts, i.e. the configured slot
-- count, not a hard cap: ESPN reports isBenchUnlimited separately and some
-- leagues allow more players than the sum. `starter_count` is the sum of the
-- starting slots (0-11); 12 is bench, 13 IR and 14 unused.
--
-- `division_id` and `division_name` are NULL when the league has zero or one
-- division. ESPN always reports at least one division, but a single entry is
-- only the default standings group covering every team; a league genuinely uses
-- divisions only when ESPN reports two or more. A real division can use id 0,
-- so NULL, not 0, is the "no division" marker.

ALTER TABLE fty.league ADD COLUMN IF NOT EXISTS roster_size bigint;
ALTER TABLE fty.league ADD COLUMN IF NOT EXISTS starter_count bigint;

ALTER TABLE fty.league_competitor ADD COLUMN IF NOT EXISTS division_id bigint;
ALTER TABLE fty.league_competitor ADD COLUMN IF NOT EXISTS division_name text;
