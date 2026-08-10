CREATE TABLE provider_connections_next (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK(provider IN ('stripe', 'paypal')),
  status TEXT NOT NULL DEFAULT 'connected' CHECK(status IN ('connected', 'revoked', 'error')),
  provider_account_id TEXT NOT NULL,
  account_label TEXT,
  access_token_ciphertext TEXT,
  refresh_token_ciphertext TEXT,
  token_expires_at TEXT,
  scope TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, provider)
);

INSERT INTO provider_connections_next (
  id, user_id, provider, status, provider_account_id, account_label,
  access_token_ciphertext, refresh_token_ciphertext, token_expires_at, scope,
  created_at, updated_at
)
SELECT
  id, user_id, provider, status, provider_account_id, account_label,
  access_token_ciphertext, refresh_token_ciphertext, token_expires_at, scope,
  created_at, updated_at
FROM provider_connections;

DROP TABLE provider_connections;
ALTER TABLE provider_connections_next RENAME TO provider_connections;
CREATE INDEX provider_connections_user_id_idx ON provider_connections(user_id);
CREATE UNIQUE INDEX provider_connections_provider_account_idx
  ON provider_connections(provider, provider_account_id);
