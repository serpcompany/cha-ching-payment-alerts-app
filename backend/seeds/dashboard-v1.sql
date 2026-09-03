-- Local-only dashboard seed for visual QA.
--
-- Run with:
--   pnpm db:seed:dashboard:local
--
-- This file intentionally relies on the package script's --local flag and
-- targets the most recent anonymous Simulator user in local Wrangler D1 state.
-- Rows use a seed-dashboard-v1-* id namespace so this can be rerun safely.

PRAGMA foreign_keys = ON;

DELETE FROM sales
WHERE id LIKE 'seed-dashboard-v1-%';

DELETE FROM custom_payment_sources
WHERE id IN (
  'seed-dashboard-v1-custom-shop',
  'seed-dashboard-v1-custom-course',
  'seed-dashboard-v1-custom-deleted'
);

DELETE FROM provider_connections
WHERE id IN (
  'seed-dashboard-v1-stripe-connection',
  'seed-dashboard-v1-paypal-connection'
);

WITH feature(value) AS (
  VALUES ('connect_stripe'), ('connect_paypal'), ('connect_custom')
)
INSERT OR IGNORE INTO entitlements (user_id, feature_key, enabled)
SELECT user.id, feature.value, 1
FROM (
  SELECT id
  FROM user
  WHERE is_anonymous = 1
  ORDER BY created_at DESC
  LIMIT 1
) AS user
CROSS JOIN feature;

INSERT INTO user_preferences (user_id, reporting_timezone)
SELECT id, 'Asia/Tokyo'
FROM user
WHERE is_anonymous = 1
ORDER BY created_at DESC
LIMIT 1
ON CONFLICT(user_id) DO NOTHING;

INSERT INTO provider_connections (
  id, user_id, provider, status, provider_account_id, account_label,
  access_token_ciphertext, refresh_token_ciphertext, scope, is_active
)
SELECT
  'seed-dashboard-v1-stripe-connection',
  id,
  'stripe',
  'connected',
  'acct_seed_dashboard_v1',
  'Stripe demo account',
  'local-seed-ciphertext',
  NULL,
  'read_only',
  1
FROM user
WHERE is_anonymous = 1
ORDER BY created_at DESC
LIMIT 1;

INSERT INTO provider_connections (
  id, user_id, provider, status, provider_account_id, account_label,
  access_token_ciphertext, refresh_token_ciphertext, scope, is_active
)
SELECT
  'seed-dashboard-v1-paypal-connection',
  id,
  'paypal',
  'connected',
  'paypal_seed_dashboard_v1',
  'PayPal demo account',
  'local-seed-ciphertext',
  NULL,
  'read_only',
  1
FROM user
WHERE is_anonymous = 1
ORDER BY created_at DESC
LIMIT 1;

INSERT INTO custom_payment_sources (
  id, user_id, name, status, webhook_token_hash, webhook_token_ciphertext,
  sample_received_at, mapping_json, last_event_received_at, last_event_status,
  last_payment_received_at
)
SELECT
  'seed-dashboard-v1-custom-shop',
  id,
  'SERP Store webhook',
  'active',
  'seed-dashboard-v1-custom-shop-hash',
  'local-seed-ciphertext',
  datetime('now', '-2 hours'),
  '{}',
  datetime('now', '-12 minutes'),
  'accepted',
  datetime('now', '-12 minutes')
FROM user
WHERE is_anonymous = 1
ORDER BY created_at DESC
LIMIT 1;

INSERT INTO custom_payment_sources (
  id, user_id, name, status, webhook_token_hash, webhook_token_ciphertext,
  sample_received_at, mapping_json, last_event_received_at, last_event_status,
  last_payment_received_at
)
SELECT
  'seed-dashboard-v1-custom-course',
  id,
  'Course platform webhook',
  'active',
  'seed-dashboard-v1-custom-course-hash',
  'local-seed-ciphertext',
  datetime('now', '-6 days'),
  '{}',
  datetime('now', '-1 day'),
  'accepted',
  datetime('now', '-1 day')
FROM user
WHERE is_anonymous = 1
ORDER BY created_at DESC
LIMIT 1;

WITH sale(
  row_id, provider, provider_account_id, amount_minor, currency, product_label,
  plan_label, sale_type_label, country_code, is_subscription, age_seconds,
  notification_fields_json, notification_field_values_json
) AS (
  VALUES
    (1, 'stripe', 'acct_seed_dashboard_v1', 13900, 'USD', 'SERP Pro', 'Monthly', 'Subscription', 'US', 1, 900,
     '[{"label":"Customer","value":"alex@example.com"},{"label":"Plan","value":"Monthly"}]',
     '[{"id":"customer","value":"alex@example.com"},{"id":"plan","value":"Monthly"}]'),
    (2, 'custom', 'seed-dashboard-v1-custom-shop', 7450, 'USD', 'Prompt Pack', NULL, 'One-time payment', 'US', 0, 2700,
     '[{"label":"Customer","value":"jordan@example.com"},{"label":"Order","value":"SERP-1042"}]',
     '[{"id":"customer","value":"jordan@example.com"},{"id":"order","value":"SERP-1042"}]'),
    (3, 'paypal', 'paypal_seed_dashboard_v1', 2999, 'USD', 'Audit Template', NULL, 'One-time payment', 'CA', 0, 7200, NULL, NULL),
    (4, 'stripe', 'acct_seed_dashboard_v1', 5100, 'USD', 'SERP Pro', 'Monthly', 'Subscription', 'US', 1, 18000,
     '[{"label":"Customer","value":"casey@example.com"},{"label":"Plan","value":"Monthly"}]',
     '[{"id":"customer","value":"casey@example.com"},{"id":"plan","value":"Monthly"}]'),
    (5, 'custom', 'seed-dashboard-v1-custom-shop', 18900, 'USD', 'Consulting call', NULL, 'One-time payment', 'GB', 0, 86400,
     '[{"label":"Customer","value":"morgan@example.com"},{"label":"Order","value":"SERP-1041"}]',
     '[{"id":"customer","value":"morgan@example.com"},{"id":"order","value":"SERP-1041"}]'),
    (6, 'stripe', 'acct_seed_dashboard_v1', 10900, 'USD', 'SERP Pro', 'Annual', 'Subscription', 'US', 1, 172800, NULL, NULL),
    (7, 'custom', 'seed-dashboard-v1-custom-course', 9900, 'USD', 'Course seat', NULL, 'One-time payment', 'AU', 0, 345600, NULL, NULL),
    (8, 'stripe', 'acct_seed_dashboard_v1', 13900, 'USD', 'SERP Pro', 'Monthly', 'Subscription', 'US', 1, 604800, NULL, NULL),
    (9, 'custom', 'seed-dashboard-v1-custom-shop', 2500, 'EUR', 'Prompt Pack', NULL, 'One-time payment', 'DE', 0, 777600, NULL, NULL),
    (10, 'paypal', 'paypal_seed_dashboard_v1', 12900, 'USD', 'Audit Template', NULL, 'One-time payment', 'US', 0, 1209600, NULL, NULL),
    (11, 'stripe', 'acct_seed_dashboard_v1', 13900, 'USD', 'SERP Pro', 'Monthly', 'Subscription', 'US', 1, 1814400, NULL, NULL),
    (12, 'custom', 'seed-dashboard-v1-custom-deleted', 3900, 'USD', 'Legacy webhook payment', NULL, 'One-time payment', 'US', 0, 2419200, NULL, NULL),
    (13, 'stripe', 'acct_seed_dashboard_v1', 7900, 'JPY', 'Japan add-on', NULL, 'One-time payment', 'JP', 0, 3024000, NULL, NULL),
    (14, 'stripe', 'acct_seed_dashboard_v1', 13900, 'USD', 'SERP Pro', 'Monthly', 'Subscription', 'US', 1, 3888000, NULL, NULL),
    (15, 'custom', 'seed-dashboard-v1-custom-shop', 4500, 'USD', 'Prompt Pack', NULL, 'One-time payment', 'US', 0, 5184000, NULL, NULL),
    (16, 'paypal', 'paypal_seed_dashboard_v1', 5900, 'USD', 'Audit Template', NULL, 'One-time payment', 'US', 0, 7776000, NULL, NULL),
    (17, 'stripe', 'acct_seed_dashboard_v1', 13900, 'USD', 'SERP Pro', 'Monthly', 'Subscription', 'US', 1, 10368000, NULL, NULL),
    (18, 'custom', 'seed-dashboard-v1-custom-course', 9900, 'USD', 'Course seat', NULL, 'One-time payment', 'US', 0, 15552000, NULL, NULL)
)
INSERT INTO sales (
  id, user_id, provider, provider_account_id, provider_event_id,
  provider_payment_id, amount_minor, currency, status, product_label,
  plan_label, sale_type_label, country_code, is_subscription, occurred_at,
  notification_fields_json, notification_field_values_json
)
SELECT
  'seed-dashboard-v1-sale-' || sale.row_id,
  user.id,
  sale.provider,
  sale.provider_account_id,
  'seed-dashboard-v1-event-' || sale.row_id,
  'seed-dashboard-v1-payment-' || sale.row_id,
  sale.amount_minor,
  sale.currency,
  'succeeded',
  sale.product_label,
  sale.plan_label,
  sale.sale_type_label,
  sale.country_code,
  sale.is_subscription,
  unixepoch('now') - sale.age_seconds,
  sale.notification_fields_json,
  sale.notification_field_values_json
FROM (
  SELECT id
  FROM user
  WHERE is_anonymous = 1
  ORDER BY created_at DESC
  LIMIT 1
) AS user
CROSS JOIN sale;
