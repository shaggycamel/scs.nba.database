-- Public read-only pass-through of statyx.schedule. scs_hub conforms these tables
-- on write, so no joins are added here. Columns bind at create time: re-run
-- scripts/apply_views.py after an ingestion schema change.
CREATE OR REPLACE VIEW statyx.schedule_vw AS
SELECT * FROM statyx.schedule;
