PRAGMA foreign_keys = ON;

CREATE TABLE provider_events (
  id TEXT PRIMARY KEY NOT NULL,
  provider TEXT NOT NULL CHECK(provider IN ('stripe', 'paypal')),
  provider_event_id TEXT NOT NULL,
  user_id TEXT REFERENCES user(id) ON DELETE SET NULL,
  provider_account_id TEXT,
  event_type TEXT NOT NULL,
  livemode INTEGER NOT NULL DEFAULT 0 CHECK(livemode IN (0, 1)),
  received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(provider, provider_event_id)
);
CREATE INDEX provider_events_user_id_idx ON provider_events(user_id);
CREATE INDEX provider_events_account_idx ON provider_events(provider, provider_account_id);

CREATE TABLE sales (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK(provider IN ('stripe', 'paypal')),
  provider_account_id TEXT NOT NULL,
  provider_event_id TEXT NOT NULL,
  provider_payment_id TEXT NOT NULL,
  amount_minor INTEGER NOT NULL CHECK(amount_minor >= 0),
  currency TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'succeeded' CHECK(status IN ('succeeded', 'refunded')),
  product_label TEXT NOT NULL,
  country_code TEXT,
  is_subscription INTEGER NOT NULL DEFAULT 0 CHECK(is_subscription IN (0, 1)),
  occurred_at INTEGER NOT NULL,
  notification_queued_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(provider, provider_event_id),
  UNIQUE(provider, provider_payment_id)
);
CREATE INDEX sales_user_occurred_at_idx ON sales(user_id, occurred_at DESC);

CREATE TABLE device_tokens (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  token TEXT NOT NULL,
  environment TEXT NOT NULL CHECK(environment IN ('development', 'production')),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'invalid')),
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, device_id),
  UNIQUE(token)
);
CREATE INDEX device_tokens_user_status_idx ON device_tokens(user_id, status);

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
CREATE INDEX notification_deliveries_status_idx ON notification_deliveries(status, updated_at);
