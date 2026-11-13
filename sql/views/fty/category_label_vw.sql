-- Read-only view over fty.category_label for the data build.
CREATE OR REPLACE VIEW fty.category_label_vw AS
SELECT
    nba_category,
    fmt_category,
    display_order,
    higher_is_better,
    numerator,
    denominator
FROM fty.category_label;
