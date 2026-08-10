CREATE TABLE custom_payment_sources (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'setup' CHECK(status IN ('setup', 'active', 'paused')),
  webhook_token_hash TEXT NOT NULL UNIQUE,
  webhook_token_ciphertext TEXT NOT NULL,
  sample_payload_ciphertext TEXT,
  sample_received_at TEXT,
  sample_error TEXT,
  mapping_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX custom_payment_sources_user_id_idx
  ON custom_payment_sources(user_id, created_at);

CREATE TABLE entitlements_next (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  feature_key TEXT NOT NULL CHECK(feature_key IN ('connect_stripe', 'connect_paypal', 'connect_custom')),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, feature_key)
);

INSERT INTO entitlements_next (id, user_id, feature_key, enabled, created_at, updated_at)
SELECT id, user_id, feature_key, enabled, created_at, updated_at FROM entitlements;
DROP TABLE entitlements;
ALTER TABLE entitlements_next RENAME TO entitlements;
CREATE INDEX entitlements_user_id_idx ON entitlements(user_id);

-- SQLite CHECK constraints cannot be widened in place. Rebuild the normalized
-- sales table so custom payment sources are represented honestly in history.
-- Preserve the child delivery rows explicitly; dropping a referenced table can
-- otherwise apply ON DELETE actions even during a schema migration.
PRAGMA foreign_keys = OFF;

CREATE TABLE notification_deliveries_backup AS
SELECT * FROM notification_deliveries;
DROP TABLE notification_deliveries;

CREATE TABLE sales_next (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK(provider IN ('stripe', 'paypal', 'custom')),
  provider_account_id TEXT NOT NULL,
  provider_event_id TEXT NOT NULL,
  provider_payment_id TEXT NOT NULL,
  amount_minor INTEGER NOT NULL CHECK(amount_minor >= 0),
  currency TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'succeeded' CHECK(status IN ('succeeded', 'refunded')),
  product_label TEXT NOT NULL,
  plan_label TEXT,
  sale_type_label TEXT,
  country_code TEXT,
  is_subscription INTEGER NOT NULL DEFAULT 0 CHECK(is_subscription IN (0, 1)),
  occurred_at INTEGER NOT NULL,
  notification_queued_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(provider, provider_event_id),
  UNIQUE(provider, provider_payment_id)
);

INSERT INTO sales_next (
  id, user_id, provider, provider_account_id, provider_event_id,
  provider_payment_id, amount_minor, currency, status, product_label,
  plan_label, sale_type_label, country_code, is_subscription, occurred_at,
  notification_queued_at, created_at
)
SELECT
  id, user_id, provider, provider_account_id, provider_event_id,
  provider_payment_id, amount_minor, currency, status, product_label,
  NULL, NULL, country_code, is_subscription, occurred_at, notification_queued_at, created_at
FROM sales;

DROP TABLE sales;
ALTER TABLE sales_next RENAME TO sales;
CREATE INDEX sales_user_occurred_at_idx ON sales(user_id, occurred_at DESC);

CREATE TABLE notification_deliveries (
  id TEXT PRIMARY KEY NOT NULL,
  sale_id TEXT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  device_token_id TEXT NOT NULL REFERENCES device_tokens(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'sending', 'retry', 'sent', 'failed')),
  attempt_count INTEGER NOT NULL DEFAULT 0,
  apns_id TEXT,
  error_code TEXT,
  last_attempt_at TEXT,
  sent_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(sale_id, device_token_id)
);

INSERT INTO notification_deliveries (
  id, sale_id, device_token_id, status, attempt_count, apns_id, error_code,
  last_attempt_at, sent_at, created_at, updated_at
)
SELECT
  id, sale_id, device_token_id, status, attempt_count, apns_id, error_code,
  last_attempt_at, sent_at, created_at, updated_at
FROM notification_deliveries_backup;

DROP TABLE notification_deliveries_backup;
CREATE INDEX notification_deliveries_status_idx
  ON notification_deliveries(status, updated_at);

PRAGMA foreign_keys = ON;
