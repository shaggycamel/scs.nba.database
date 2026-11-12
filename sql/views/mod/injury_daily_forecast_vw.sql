-- Public read-only view over the private model table.
CREATE OR REPLACE VIEW mod.injury_daily_forecast_vw AS
SELECT * FROM mod.injury_daily_forecast_base;
