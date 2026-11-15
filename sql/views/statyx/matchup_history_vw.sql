-- Public read-only pass-through of statyx.matchup_history. scs_hub conforms these tables
-- on write, so no joins are added here. Columns bind at create time: re-run
-- scripts/apply_views.py after an ingestion schema change.
CREATE OR REPLACE VIEW statyx.matchup_history_vw AS
SELECT * FROM statyx.matchup_history;
