-- Read-only view over nba.key_dates for the data build. season_segments_vw
-- cannot be used because it excludes All Star.
CREATE OR REPLACE VIEW nba.key_dates_vw AS
SELECT
    season,
    season_type,
    begin_date,
    end_date
FROM nba.key_dates;
