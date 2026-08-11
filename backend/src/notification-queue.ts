import type { Env } from "./env";

interface QueueStateRow {
  notification_queue_state: "claimed" | "accepted" | null;
}

/**
 * Claims and enqueues one sale. A stale claim is reclaimable after five
 * minutes. Duplicate Queue messages are safe because delivery is claimed by
 * the unique sale/device row and reuses its stable APNs id.
 */
export async function enqueueSaleNotification(env: Env, saleId: string): Promise<boolean> {
  const claimed = await env.DB.prepare(
    `UPDATE sales
     SET notification_queue_state = 'claimed',
         notification_queue_claimed_at = CURRENT_TIMESTAMP,
         notification_queued_at = NULL
     WHERE id = ?1
       AND (
         notification_queue_state IS NULL
         OR (
           notification_queue_state = 'claimed'
           AND (
             notification_queue_claimed_at IS NULL
             OR notification_queue_claimed_at <= datetime('now', '-5 minutes')
           )
         )
       )
     RETURNING id`,
  ).bind(saleId).first<{ id: string }>();
  if (!claimed) {
    const existing = await env.DB.prepare(
      "SELECT notification_queue_state FROM sales WHERE id = ?1",
    ).bind(saleId).first<QueueStateRow>();
    if (existing?.notification_queue_state === "accepted") return false;
    if (existing?.notification_queue_state === "claimed") {
      throw new Error("Notification queue claim is still pending");
    }
    throw new Error("Sale could not be claimed for notification");
  }

  try {
    await env.NOTIFICATION_QUEUE.send({ saleId });
  } catch (error) {
    await env.DB.prepare(
      `UPDATE sales
       SET notification_queue_state = NULL,
           notification_queue_claimed_at = NULL,
           notification_queued_at = NULL
       WHERE id = ?1 AND notification_queue_state = 'claimed'`,
    ).bind(saleId).run();
    throw error;
  }

  await env.DB.prepare(
    `UPDATE sales
     SET notification_queue_state = 'accepted',
         notification_queue_claimed_at = NULL,
         notification_queued_at = CURRENT_TIMESTAMP
     WHERE id = ?1 AND notification_queue_state = 'claimed'`,
  ).bind(saleId).run();
  return true;
}
