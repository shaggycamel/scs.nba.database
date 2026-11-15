-- Public read-only pass-through of statyx.game_stats. scs_hub conforms these tables
-- on write, so no joins are added here. Columns bind at create time: re-run
-- scripts/apply_views.py after an ingestion schema change.
CREATE OR REPLACE VIEW statyx.game_stats_vw AS
SELECT * FROM statyx.game_stats;
