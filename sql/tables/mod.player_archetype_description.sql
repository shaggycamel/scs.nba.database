-- Reference DDL and seed for the archetype descriptions. This is the single
-- source of the human-readable names; changing a description is an UPDATE here
-- and never an ALTER of a fact table or view.
CREATE TABLE IF NOT EXISTS mod.player_archetype_description_base (
    archetype_label INT8 PRIMARY KEY,
    archetype_description TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO mod.player_archetype_description_base (archetype_label, archetype_description)
VALUES
    (0, 'Playmaking guard'),
    (1, 'Spot-up wing'),
    (2, 'Rebounding forward'),
    (3, 'Interior finisher'),
    (4, 'Rim-running center'),
    (5, 'Perimeter defensive wing'),
    (6, 'Rim-protecting big'),
    (7, 'Secondary creator'),
    (8, 'Scoring wing'),
    (9, 'Floor spacer')
ON CONFLICT (archetype_label) DO UPDATE SET
    archetype_description = EXCLUDED.archetype_description,
    updated_at = now();
