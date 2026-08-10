import { createHash } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../config/main";

export type UnreadKind = "messages" | "orders";

export type UnreadCounts = {
  messages: number;
  orders: number;
  total: number;
};

type MessageEntry = Record<string, unknown>;

function count(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
}

function hasNumber(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value);
}

function digits(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "");
}

export function customerNumbersMatch(left: unknown, right: unknown): boolean {
  const a = digits(left);
  const b = digits(right);
  if (!a || !b) return false;
  const comparableLength = Math.min(9, a.length, b.length);
  return a.slice(-comparableLength) === b.slice(-comparableLength);
}

export function isUnreadInboundMessage(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const message = value as MessageEntry;
  const direction = String(message.direction ?? "inbound").toLowerCase();
  return direction === "inbound" && message.isRead !== true;
}

/**
 * Counts the released unreadMessages[] truth surface. Older releases never
 * initialized a per-customer unread counter, so this array is the migration
 * source of truth for those customers.
 */
export function legacyUnreadMessageCount(
  value: FirebaseFirestore.DocumentData | undefined,
  customerNumber?: unknown,
): number {
  const entries = Array.isArray(value?.unreadMessages)
    ? (value?.unreadMessages as unknown[])
    : [];
  return entries.filter(
    (entry) =>
      isUnreadInboundMessage(entry) &&
      (customerNumber == null ||
        customerNumbersMatch(
          (entry as MessageEntry).customerNumber,
          customerNumber,
        )),
  ).length;
}

/**
 * Resolves the released customer phone fields before deriving that customer's
 * unreadMessages[] baseline. Returning undefined is intentional: when no
 * customer number is known, a global merchant message count must never be
 * copied onto one customer.
 */
export function legacyUnreadMessageCountForCustomer(
  merchant: FirebaseFirestore.DocumentData | undefined,
  customer: FirebaseFirestore.DocumentData | undefined,
  suppliedCustomerNumber?: unknown,
): number | undefined {
  const rawNumber = [
    suppliedCustomerNumber,
    customer?.number,
    customer?.phoneNumber,
    customer?.mobileNumber,
  ].find((value) => String(value ?? "").trim());
  if (rawNumber == null) return undefined;
  return legacyUnreadMessageCount(merchant, rawNumber);
}

export function canonicalUnreadCounts(
  value: FirebaseFirestore.DocumentData | undefined,
  options: { legacyMessageCount?: number } = {},
): UnreadCounts {
  const nested =
    value?.unreadCounts && typeof value.unreadCounts === "object"
      ? value.unreadCounts
      : {};
  const nestedMessages = hasNumber(nested.messages)
    ? count(nested.messages)
    : count(value?.unreadCount);
  const messages = Math.max(nestedMessages, count(options.legacyMessageCount));
  const orders = hasNumber(nested.orders)
    ? count(nested.orders)
    : count(value?.ordersUnreadCount);
  return { messages, orders, total: messages + orders };
}

export function unreadEventDocumentId(eventKey: string): string {
  return createHash("sha256").update(eventKey).digest("hex");
}

function withTotal(counts: Omit<UnreadCounts, "total">): UnreadCounts {
  return {
    ...counts,
    total: counts.messages + counts.orders,
  };
}

function subtractCount(
  counts: UnreadCounts,
  kind: UnreadKind,
  amount: number,
): UnreadCounts {
  return withTotal({
    messages:
      kind === "messages"
        ? Math.max(0, counts.messages - amount)
        : counts.messages,
    orders:
      kind === "orders" ? Math.max(0, counts.orders - amount) : counts.orders,
  });
}

function counterUpdate(counts: UnreadCounts) {
  return {
    unreadCounts: {
      messages: counts.messages,
      orders: counts.orders,
      total: counts.total,
      updatedAt: FieldValue.serverTimestamp(),
    },
    // Released clients still read these scalar fields. Keep them in lockstep
    // for at least one compatibility release.
    unreadCount: counts.messages,
    ordersUnreadCount: counts.orders,
  };
}

/**
 * Increments one merchant/customer unread counter exactly once per event key.
 * A message entry can be supplied so truth-surface storage, the event marker,
 * and both counters commit atomically. This prevents a read racing between an
 * array append and a separate counter increment.
 */
export async function incrementUnreadCount(args: {
  merchantId: string;
  customerId?: string;
  customerNumber?: unknown;
  kind: UnreadKind;
  eventKey: string;
  messageEntry?: MessageEntry;
  notification?: {
    ref: FirebaseFirestore.DocumentReference;
    data: FirebaseFirestore.DocumentData;
  };
}): Promise<{
  merchant: UnreadCounts;
  customer: UnreadCounts;
  deduped: boolean;
  eventId: string;
  notificationCreated: boolean;
}> {
  const merchantRef = db.doc(`users/${args.merchantId}`);
  const customerRef = args.customerId
    ? merchantRef.collection("customers").doc(args.customerId)
    : null;
  const eventId = unreadEventDocumentId(args.eventKey);
  const eventRef = merchantRef.collection("unreadEvents").doc(eventId);

  return db.runTransaction(async (tx) => {
    const [event, merchant, customer, notification] = await Promise.all([
      tx.get(eventRef),
      tx.get(merchantRef),
      customerRef ? tx.get(customerRef) : Promise.resolve(null),
      args.notification ? tx.get(args.notification.ref) : Promise.resolve(null),
    ]);
    if (!merchant.exists) {
      throw new Error("MERCHANT_NOT_FOUND");
    }
    const merchantData = merchant.data();
    const merchantCounts = canonicalUnreadCounts(merchantData, {
      legacyMessageCount: legacyUnreadMessageCount(merchantData),
    });
    const customerCounts = canonicalUnreadCounts(customer?.data(), {
      legacyMessageCount: legacyUnreadMessageCountForCustomer(
        merchantData,
        customer?.data(),
        args.customerNumber,
      ),
    });
    if (event.exists) {
      const notificationCreated = Boolean(
        args.notification && !notification?.exists,
      );
      if (args.notification && !notification?.exists) {
        tx.create(args.notification.ref, args.notification.data);
      }
      return {
        merchant: merchantCounts,
        customer: customerCounts,
        deduped: true,
        eventId,
        notificationCreated,
      };
    }

    const nextMerchant = withTotal({
      messages: merchantCounts.messages + (args.kind === "messages" ? 1 : 0),
      orders: merchantCounts.orders + (args.kind === "orders" ? 1 : 0),
    });
    const nextCustomer = withTotal({
      messages: customerCounts.messages + (args.kind === "messages" ? 1 : 0),
      orders: customerCounts.orders + (args.kind === "orders" ? 1 : 0),
    });

    tx.create(eventRef, {
      eventKey: args.eventKey.slice(0, 500),
      kind: args.kind,
      customerId: args.customerId ?? null,
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
    const notificationCreated = Boolean(
      args.notification && !notification?.exists,
    );
    if (args.notification && !notification?.exists) {
      tx.create(args.notification.ref, args.notification.data);
    }
    tx.set(
      merchantRef,
      {
        ...counterUpdate(nextMerchant),
        ...(args.messageEntry
          ? {
              unreadMessages: FieldValue.arrayUnion({
                ...args.messageEntry,
                unreadEventId: eventId,
                isRead: false,
              }),
            }
          : {}),
      },
      { merge: true },
    );
    if (customerRef && customer?.exists) {
      tx.set(customerRef, counterUpdate(nextCustomer), { merge: true });
    }
    return {
      merchant: nextMerchant,
      customer: nextCustomer,
      deduped: false,
      eventId,
      notificationCreated,
    };
  });
}

/** Atomically appends a non-unread truth-surface entry (for example bot output). */
export async function appendTruthSurfaceMessage(args: {
  merchantId: string;
  messageEntry: MessageEntry;
  externalId?: string;
}): Promise<{ deduped: boolean }> {
  const merchantRef = db.doc(`users/${args.merchantId}`);
  return db.runTransaction(async (tx) => {
    const merchant = await tx.get(merchantRef);
    if (!merchant.exists) throw new Error("MERCHANT_NOT_FOUND");
    const entries = Array.isArray(merchant.data()?.unreadMessages)
      ? (merchant.data()?.unreadMessages as MessageEntry[])
      : [];
    if (
      args.externalId &&
      entries.some((entry) => entry.externalId === args.externalId)
    ) {
      return { deduped: true };
    }
    tx.update(merchantRef, {
      unreadMessages: FieldValue.arrayUnion(args.messageEntry),
    });
    return { deduped: false };
  });
}

export function markMatchingMessagesRead(args: {
  messages: unknown[];
  customerNumber: unknown;
  limit: number;
  readAt: string;
}): { messages: unknown[]; marked: number } {
  let marked = 0;
  const messages = args.messages.map((value) => {
    if (
      marked < args.limit &&
      isUnreadInboundMessage(value) &&
      customerNumbersMatch(
        (value as MessageEntry).customerNumber,
        args.customerNumber,
      )
    ) {
      marked += 1;
      return { ...(value as MessageEntry), isRead: true, readAt: args.readAt };
    }
    return value;
  });
  return { messages, marked };
}

/**
 * Marks only the bounded messages selected inside this transaction and
 * subtracts exactly that delta. Any arrival concurrent with the request makes
 * the transaction retry and remains unread unless it falls within the bound.
 */
export async function markCustomerMessagesRead(args: {
  merchantId: string;
  customerId?: string;
  customerNumber: unknown;
  limit: number;
}): Promise<{ cleared: number; counts: UnreadCounts }> {
  const merchantRef = db.doc(`users/${args.merchantId}`);
  const customerRef = args.customerId
    ? merchantRef.collection("customers").doc(args.customerId)
    : null;
  return db.runTransaction(async (tx) => {
    const [merchant, customer] = await Promise.all([
      tx.get(merchantRef),
      customerRef ? tx.get(customerRef) : Promise.resolve(null),
    ]);
    if (!merchant.exists) throw new Error("MERCHANT_NOT_FOUND");
    const merchantData = merchant.data();
    const beforeMessages = Array.isArray(merchantData?.unreadMessages)
      ? (merchantData?.unreadMessages as unknown[])
      : [];
    const result = markMatchingMessagesRead({
      messages: beforeMessages,
      customerNumber: args.customerNumber,
      limit: args.limit,
      readAt: new Date().toISOString(),
    });

    const merchantCounts = canonicalUnreadCounts(merchantData, {
      legacyMessageCount: legacyUnreadMessageCount(merchantData),
    });
    const nextMerchant = subtractCount(
      merchantCounts,
      "messages",
      result.marked,
    );
    tx.set(
      merchantRef,
      {
        ...counterUpdate(nextMerchant),
        ...(result.marked ? { unreadMessages: result.messages } : {}),
      },
      { merge: true },
    );

    if (customerRef && customer?.exists) {
      const customerCounts = canonicalUnreadCounts(customer?.data(), {
        legacyMessageCount: legacyUnreadMessageCountForCustomer(
          merchantData,
          customer?.data(),
          args.customerNumber,
        ),
      });
      tx.set(
        customerRef,
        counterUpdate(subtractCount(customerCounts, "messages", result.marked)),
        { merge: true },
      );
    }
    return { cleared: result.marked, counts: nextMerchant };
  });
}

type OrderNotificationSelection = {
  id: string;
  customerId?: string;
  unreadEventId?: string;
};

/**
 * Marks only the notification IDs supplied by a bounded query. Notification
 * reads and counter deltas share a transaction, so retrying a clear cannot
 * double-subtract and a concurrent order that was not scanned stays unread.
 */
export async function markOrderNotificationsRead(args: {
  merchantId: string;
  notificationIds: string[];
  customerId?: string;
}): Promise<{ cleared: number; counts: UnreadCounts }> {
  const merchantRef = db.doc(`users/${args.merchantId}`);
  // One selected notification can write its notification, event marker, and
  // customer. 150 therefore stays below Firestore's 500-write transaction
  // ceiling even when every order belongs to a different customer.
  const notificationRefs = [...new Set(args.notificationIds)]
    .slice(0, 150)
    .map((id) => merchantRef.collection("notifications").doc(id));

  return db.runTransaction(async (tx) => {
    const [merchant, ...notificationDocs] = await Promise.all([
      tx.get(merchantRef),
      ...notificationRefs.map((ref) => tx.get(ref)),
    ]);
    if (!merchant.exists) throw new Error("MERCHANT_NOT_FOUND");

    const selected: OrderNotificationSelection[] = [];
    notificationDocs.forEach((notification) => {
      const data = notification.data();
      if (
        !notification.exists ||
        data?.type !== "ORDER_EVENT" ||
        data?.read === true
      ) {
        return;
      }
      const customerId = String(data?.customerId ?? "").trim() || undefined;
      if (args.customerId && customerId !== args.customerId) return;
      selected.push({
        id: notification.id,
        customerId,
        unreadEventId: String(data?.unreadEventId ?? "").trim() || undefined,
      });
    });

    const eventIds = [
      ...new Set(
        selected
          .map((item) => item.unreadEventId)
          .filter((id): id is string => Boolean(id)),
      ),
    ];
    const eventRefs = eventIds.map((id) =>
      merchantRef.collection("unreadEvents").doc(id),
    );
    const eventDocs = await Promise.all(eventRefs.map((ref) => tx.get(ref)));
    const eventUnread = new Map(
      eventDocs.map((event) => [
        event.id,
        event.exists &&
          event.data()?.kind === "orders" &&
          event.data()?.readAt == null,
      ]),
    );

    const customerDeltas = new Map<string, number>();
    const countedEvents = new Set<string>();
    let merchantDelta = 0;
    for (const item of selected) {
      let shouldDecrement = !item.unreadEventId;
      if (
        item.unreadEventId &&
        eventUnread.get(item.unreadEventId) === true &&
        !countedEvents.has(item.unreadEventId)
      ) {
        shouldDecrement = true;
        countedEvents.add(item.unreadEventId);
      }
      if (!shouldDecrement) continue;
      merchantDelta += 1;
      if (item.customerId) {
        customerDeltas.set(
          item.customerId,
          (customerDeltas.get(item.customerId) ?? 0) + 1,
        );
      }
    }

    const customerEntries = [...customerDeltas.entries()];
    const customerDocs = await Promise.all(
      customerEntries.map(([customerId]) =>
        tx.get(merchantRef.collection("customers").doc(customerId)),
      ),
    );
    const merchantCounts = canonicalUnreadCounts(merchant.data(), {
      legacyMessageCount: legacyUnreadMessageCount(merchant.data()),
    });
    const nextMerchant = subtractCount(merchantCounts, "orders", merchantDelta);
    selected.forEach((item) => {
      tx.update(merchantRef.collection("notifications").doc(item.id), {
        read: true,
        readAt: FieldValue.serverTimestamp(),
      });
    });
    countedEvents.forEach((eventId) => {
      tx.update(merchantRef.collection("unreadEvents").doc(eventId), {
        readAt: FieldValue.serverTimestamp(),
      });
    });
    tx.set(merchantRef, counterUpdate(nextMerchant), { merge: true });
    customerEntries.forEach(([customerId, delta], index) => {
      if (!customerDocs[index]?.exists) return;
      const ref = merchantRef.collection("customers").doc(customerId);
      const customerData = customerDocs[index]?.data();
      const current = canonicalUnreadCounts(customerData, {
        legacyMessageCount: legacyUnreadMessageCountForCustomer(
          merchant.data(),
          customerData,
        ),
      });
      tx.set(ref, counterUpdate(subtractCount(current, "orders", delta)), {
        merge: true,
      });
    });
    return { cleared: merchantDelta, counts: nextMerchant };
  });
}
