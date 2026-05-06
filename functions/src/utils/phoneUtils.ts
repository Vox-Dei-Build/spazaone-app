import { db } from "../config/main";

/**
 * Handles Firestore exceptions and logs errors.
 *
 * @template T
 * @param {any} action - The action to be performed.
 * @param {string} errorMessage - The error message to log if the action fails.
 */
async function firestoreExceptionHandler<T>(
  action: () => Promise<T>,
  errorMessage: string,
): Promise<T | null> {
  try {
    return await action();
  } catch (error) {
    console.error(`${errorMessage}: ${error}`);
    return null;
  }
}

/**
 * Strict SA mobile number detection.
 *
 * All conversions in this file are SA-only and never silently mangle
 * non-SA input. If the input cannot be confidently identified as a SA
 * mobile number, an empty string is returned and downstream validators
 * will reject it via {@link isValidSAPhoneNumber}.
 *
 * Accepted SA mobile prefixes: 6, 7, 8, 9 (per ICASA, including the
 * 9-prefix range allocated from 2024 onwards).
 *
 * NOTE: This file is the single source of truth for phone-number
 * handling in functions/. Do not introduce new normalizers; import
 * from here.
 */

const SA_LOCAL_REGEX = /^0[6-9][0-9]{8}$/;
const SA_E164_REGEX = /^\+27[6-9][0-9]{8}$/;
const SA_CC_DIGITS_REGEX = /^27[6-9][0-9]{8}$/;

/**
 * Returns the number in E.164 format (`+27XXXXXXXXX`) if it is a valid
 * SA mobile, otherwise an empty string. Never blindly prepends `+27`.
 *
 * @param {string | null | undefined} phoneNumber - Raw input.
 * @return {string} - The E.164 SA number, or "" if not SA-valid.
 */
export function formatPhoneNumber(
  phoneNumber: string | null | undefined,
): string {
  if (!phoneNumber) return "";

  const trimmed = phoneNumber.trim();
  if (trimmed === "") return "";

  const hasPlusPrefix = trimmed.startsWith("+");
  const digits = cleanPhoneNumber(trimmed);

  if (SA_LOCAL_REGEX.test(digits)) {
    return "+27" + digits.substring(1);
  }
  if (SA_CC_DIGITS_REGEX.test(digits)) {
    return "+" + digits;
  }
  if (hasPlusPrefix && SA_E164_REGEX.test("+" + digits)) {
    return "+" + digits;
  }
  return "";
}

/**
 * Normalizes to local SA form (`0XXXXXXXXX`). Returns empty string if
 * the number is not a valid SA mobile.
 *
 * @param {string | null | undefined} rawNumber - Raw input.
 * @return {string} - The local SA number, or "" if not SA-valid.
 */
export function normalizePhoneNumber(
  rawNumber: string | null | undefined,
): string {
  if (!rawNumber) return "";
  const e164 = formatPhoneNumber(rawNumber);
  if (e164 === "") return "";
  return "0" + e164.substring(3);
}

/**
 * Validates a South African mobile phone number.
 *
 * @param {string | null | undefined} phoneNumber - The phone number to validate.
 * @return {boolean} - true iff a valid SA mobile.
 */
export function isValidSAPhoneNumber(
  phoneNumber: string | null | undefined,
): boolean {
  if (!phoneNumber) return false;
  return formatPhoneNumber(phoneNumber) !== "";
}

/**
 * Fetches and formats a customer's phone number from Firestore.
 *
 * @param {string} currentUserId - The user ID (merchant).
 * @param {string} customerId - The customer ID.
 * @return {Promise<string | null>} - The E.164 formatted number, or null on error.
 */
export async function fetchAndFormatPhoneNumber(
  currentUserId: string,
  customerId: string,
): Promise<string | null> {
  return firestoreExceptionHandler(async () => {
    const phoneNumber = await getCustomerPhoneNumber(currentUserId, customerId);
    return formatPhoneNumber(phoneNumber);
  }, "Error occurred while fetching and formatting phone number");
}

/**
 * Retrieves the customer's phone number from Firestore.
 *
 * @param {string} currentUserId - The user ID (merchant).
 * @param {string} customerId - The customer ID.
 * @return {Promise<string | null>} - Returns the customer's phone number or null if not found.
 */
async function getCustomerPhoneNumber(
  currentUserId: string,
  customerId: string,
): Promise<string | null> {
  const customerDoc = await db
    .collection("users")
    .doc(currentUserId)
    .collection("customers")
    .doc(customerId)
    .get();
  const dataMap = customerDoc.data();
  return dataMap ? (dataMap["number"] as string) : null;
}

/**
 * Cleans a phone number by removing non-numeric characters.
 *
 * @param {string} phoneNumber - The phone number to clean.
 * @return {string} - Returns the cleaned phone number.
 */
function cleanPhoneNumber(phoneNumber: string): string {
  return phoneNumber.replace(/\D/g, "");
}

/**
 * Fetches the shop name for a user from Firestore.
 *
 * @param {string} currentUserId - The user ID (merchant).
 * @return {Promise<string | null>} - Returns the shop name or null if not found.
 */
export async function fetchShopNameForUser(
  currentUserId: string,
): Promise<string | null> {
  const snapshot = await db.collection("users").doc(currentUserId).get();
  const dataMap = snapshot.data();
  return dataMap ? (dataMap["shopName"] as string) : null;
}
