-- Public read-only view over the private team archetype summary. One row per
-- team-game-archetype: three shares (rolling expected starters, actual
-- starters, available players) and the top three players for that style.
CREATE OR REPLACE VIEW mod.team_archetype_summary_vw AS
SELECT * FROM mod.team_archetype_summary_base;
