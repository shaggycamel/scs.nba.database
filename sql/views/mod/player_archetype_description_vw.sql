-- Public read of the archetype descriptions. Labels are stable for the current
-- model; update the base table when a refit renames them.
CREATE OR REPLACE VIEW mod.player_archetype_description_vw AS
SELECT
    archetype_label,
    archetype_description,
    updated_at
FROM mod.player_archetype_description_base;
