-- Public read-only view over the private model table.
CREATE OR REPLACE VIEW mod.team_hierarchy_vw AS
SELECT * FROM mod.team_hierarchy_base;
