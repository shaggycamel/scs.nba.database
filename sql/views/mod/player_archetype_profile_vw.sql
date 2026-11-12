-- Public read-only view over the private model table.
CREATE OR REPLACE VIEW mod.player_archetype_profile_vw AS
SELECT * FROM mod.player_archetype_profile_base;
