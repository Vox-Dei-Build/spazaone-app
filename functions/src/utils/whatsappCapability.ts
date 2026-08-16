import { FieldValue } from "firebase-admin/firestore";
import { db } from "../config/main";
import { normalizePhoneNumber } from "./phoneUtils";

export type WhatsAppCapability = "whatsapp" | "sms" | "unknown";

const CAPABILITY_TTL_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;

type TimestampLike = {
  toDate?: () => Date;
};

export interface WhatsAppCapabilityRecord {
  hasWhatsApp?: unknown;
  lastChecked?: unknown;
}

function toDate(value: unknown): Date | null {
  if (value instanceof Date) return value;
  if (value && typeof value === "object") {
    const timestamp = value as TimestampLike;
    if (typeof timestamp.toDate === "function") {
      const date = timestamp.toDate();
      return Number.isNaN(date.getTime()) ? null : date;
    }
  }
  return null;
}

/**
 * Converts a stored WhatsApp capability record into the channel decision used
 * by campaign preparation.
 *
 * Positive records remain WhatsApp-capable. Negative records are trusted for
 * 30 days, after which they become unknown and should be rechecked by a real
 * WhatsApp delivery attempt.
 */
export function classifyWhatsAppCapability(
  record: WhatsAppCapabilityRecord | null,
  now = new Date(),
): WhatsAppCapability {
  if (!record) return "unknown";
  if (record.hasWhatsApp === true) return "whatsapp";
  if (record.hasWhatsApp !== false) return "unknown";

  const lastChecked = toDate(record.lastChecked);
  if (!lastChecked) return "unknown";

  const ageMs = now.getTime() - lastChecked.getTime();
  if (ageMs < 0 || ageMs <= CAPABILITY_TTL_DAYS * DAY_MS) {
    return "sms";
  }
  return "unknown";
}

/**
 * Reads WhatsApp capability by normalized phone number.
 *
 * New records store `phoneNumber` as a field. Older records may instead use
 * the normalized phone number as the Firestore document ID, so both shapes are
 * supported during the migration period.
 */
export async function fetchWhatsAppCapability(
  phoneNumber: string,
  now = new Date(),
): Promise<WhatsAppCapability> {
  const normalized = normalizePhoneNumber(phoneNumber);
  if (!normalized) return "unknown";

  const collection = db.collection("successfulWhatsAppNumbers");
  const querySnapshot = await collection
    .where("phoneNumber", "==", normalized)
    .limit(1)
    .get();

  if (!querySnapshot.empty) {
    return classifyWhatsAppCapability(querySnapshot.docs[0].data(), now);
  }

  const legacyDocument = await collection.doc(normalized).get();
  if (!legacyDocument.exists) return "unknown";

  return classifyWhatsAppCapability(legacyDocument.data() ?? null, now);
}

/**
 * Persist a provider-backed WhatsApp capability result without creating
 * duplicate records when an older random-id document already exists.
 *
 * The normalized phone number remains the only customer identifier stored on
 * this global capability surface. Callers must not attach provider payloads,
 * profile data, merchant ids, or message content.
 */
export async function storeWhatsAppCapability(
  phoneNumber: string,
  hasWhatsApp: boolean,
): Promise<void> {
  const normalized = normalizePhoneNumber(phoneNumber);
  if (!normalized) return;

  const collection = db.collection("successfulWhatsAppNumbers");
  const existing = await collection
    .where("phoneNumber", "==", normalized)
    .limit(1)
    .get();
  // A deterministic id makes concurrent first writes converge. Existing
  // random-id records remain supported and are updated in place.
  const ref = existing.empty
    ? collection.doc(normalized)
    : existing.docs[0].ref;
  await ref.set(
    {
      phoneNumber: normalized,
      hasWhatsApp,
      lastChecked: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}
