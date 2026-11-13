-- Read-only view over fty.customer for the entry app. It exposes password_hash
-- because the app verifies credentials; grant SELECT to kobe_public on this view,
-- not on the base table.
CREATE OR REPLACE VIEW fty.customer_vw AS
SELECT
    customer_id,
    name,
    slug,
    email,
    password_hash,
    created_at
FROM fty.customer;
