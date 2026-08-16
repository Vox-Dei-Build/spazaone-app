import { functions } from "../config/main";
import { processCommerceNotificationOutbox } from "./notifications";
import { processOrderCreatedNotificationOutbox } from "./orderCreatedNotificationOutbox";

export async function processAllCommerceNotificationOutboxes(
  limit = 20,
): Promise<{ orderCreated: number; statusUpdates: number }> {
  const [orderCreated, statusUpdates] = await Promise.all([
    processOrderCreatedNotificationOutbox(limit),
    processCommerceNotificationOutbox(limit),
  ]);
  return { orderCreated, statusUpdates };
}

export const retryCommerceOrderNotifications = functions
  .runWith({
    timeoutSeconds: 120,
    memory: "256MB",
    secrets: ["BOTPRESS_PAYMENT_REQUEST_WEBHOOK_SECRET"],
  })
  .pubsub.schedule("every 2 minutes")
  .onRun(async () => {
    await processAllCommerceNotificationOutboxes();
  });
