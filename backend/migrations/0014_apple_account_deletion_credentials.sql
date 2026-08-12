CREATE TABLE apple_account_credentials (
  user_id TEXT PRIMARY KEY NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  apple_subject TEXT NOT NULL UNIQUE,
  client_id TEXT NOT NULL,
  refresh_token_ciphertext TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
