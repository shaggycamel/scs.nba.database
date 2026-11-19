-- Public lookup for the archetype descriptions, keyed by model version. The
-- labels are only meaningful within one seasonal fit, so the version is part
-- of the key.
CREATE OR REPLACE VIEW mod.player_archetype_lookup_vw AS
SELECT
    model_version,
    archetype_label,
    archetype_description,
    n,
    model_cutoff,
    generated_at
FROM mod.player_archetype_lookup_base;
