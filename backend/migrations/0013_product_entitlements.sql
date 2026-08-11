CREATE TABLE product_entitlements (
  user_id TEXT PRIMARY KEY NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  product_key TEXT NOT NULL DEFAULT 'full_access' CHECK(product_key = 'full_access'),
  billing_provider TEXT NOT NULL DEFAULT 'apple' CHECK(billing_provider = 'apple'),
  app_account_token TEXT NOT NULL UNIQUE,
  provider_product_id TEXT,
  provider_original_transaction_id TEXT UNIQUE,
  provider_transaction_id TEXT,
  access_expires_at INTEGER,
  revoked_at INTEGER,
  provider_event_signed_at INTEGER,
  verified_at INTEGER,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX product_entitlements_access_idx
  ON product_entitlements(access_expires_at, revoked_at);
