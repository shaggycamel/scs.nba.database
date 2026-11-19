-- Reference DDL for the archetype description lookup. The player_archetypes
-- publisher creates this table with CREATE TABLE IF NOT EXISTS; the database is
-- the system of record. kobe_public reads the view, not this table.
CREATE TABLE IF NOT EXISTS mod.player_archetype_lookup_base (
    model_version TEXT NOT NULL,
    archetype_label INT8 NOT NULL,
    archetype_description TEXT,
    n INT8,
    model_cutoff DATE,
    generated_at TIMESTAMPTZ,
    PRIMARY KEY (model_version, archetype_label)
);
