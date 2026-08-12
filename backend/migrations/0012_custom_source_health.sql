ALTER TABLE custom_payment_sources
ADD COLUMN last_event_received_at TEXT;

ALTER TABLE custom_payment_sources
ADD COLUMN last_event_status TEXT
CHECK(last_event_status IN ('received', 'accepted', 'duplicate', 'rejected', 'ignored'));

ALTER TABLE custom_payment_sources
ADD COLUMN last_event_error TEXT;

ALTER TABLE custom_payment_sources
ADD COLUMN last_payment_received_at TEXT;

ALTER TABLE custom_payment_sources
ADD COLUMN health_alerted_at TEXT;

-- Existing normalized payments prove that the source was receiving events.
-- Use only server receipt time; raw payloads remain unavailable by design.
UPDATE custom_payment_sources
SET last_event_received_at = (
      SELECT MAX(created_at) FROM sales
      WHERE provider = 'custom' AND provider_account_id = custom_payment_sources.id
    ),
    last_event_status = 'accepted',
    last_payment_received_at = (
      SELECT MAX(created_at) FROM sales
      WHERE provider = 'custom' AND provider_account_id = custom_payment_sources.id
    )
WHERE EXISTS (
  SELECT 1 FROM sales
  WHERE provider = 'custom' AND provider_account_id = custom_payment_sources.id
);
