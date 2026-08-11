ALTER TABLE provider_events
ADD COLUMN disposition TEXT NOT NULL DEFAULT 'ignored'
CHECK(disposition IN ('received', 'ignored', 'processed'));

-- Backfill existing successful deliveries. An event whose sale still has no
-- queued notification remains recoverable; unmatched events stay ignored.
UPDATE provider_events
SET disposition = CASE
  WHEN EXISTS (
    SELECT 1 FROM sales
    WHERE sales.provider = provider_events.provider
      AND sales.provider_event_id = provider_events.provider_event_id
      AND sales.notification_queued_at IS NULL
  ) THEN 'received'
  WHEN EXISTS (
    SELECT 1 FROM sales
    WHERE sales.provider = provider_events.provider
      AND sales.provider_event_id = provider_events.provider_event_id
  ) THEN 'processed'
  ELSE 'ignored'
END;
