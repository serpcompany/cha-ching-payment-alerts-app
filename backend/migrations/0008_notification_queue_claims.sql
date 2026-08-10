ALTER TABLE sales
ADD COLUMN notification_queue_state TEXT
CHECK(notification_queue_state IN ('claimed', 'accepted'));

ALTER TABLE sales
ADD COLUMN notification_queue_claimed_at TEXT;

-- Existing notification_queued_at values were written only around a Queue
-- send attempt. Treat them as accepted during the migration; new writes use a
-- reclaimable claimed state before Queue acceptance.
UPDATE sales
SET notification_queue_state = 'accepted'
WHERE notification_queued_at IS NOT NULL;
