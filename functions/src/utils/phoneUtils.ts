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
 * Formats phone numbers to South African international format.
 *
 * @param {string | null} phoneNumber - The phone number to format.
 * @return {string} - The formatted phone number.
 */
function formatPhoneNumber(phoneNumber: string | null): string {
  if (!phoneNumber || phoneNumber.trim() === "") return "";

  phoneNumber = cleanPhoneNumber(phoneNumber);

  if (phoneNumber.length === 10 && phoneNumber.startsWith("0")) {
    return "+27" + phoneNumber.substring(1);
  } else if (phoneNumber.startsWith("27") && phoneNumber.length === 11) {
    return "+" + phoneNumber;
  }

  return phoneNumber;
}

/**
 * Validates a South African phone number.
 *
 * @param {string | null} phoneNumber - The phone number to validate.
 * @return {boolean} - Returns true if valid, false otherwise.
 */
export function isValidSAPhoneNumber(phoneNumber: string | null): boolean {
  if (!phoneNumber) return false;

  phoneNumber = formatPhoneNumber(phoneNumber);

  const regex = /^(?:\+27)[6-8][0-9]{8}$/;
  return regex.test(phoneNumber);
}

/**
 * Fetches and formats a customer's phone number from Firestore.
 *
 * @param {string} currentUserId - The user ID (merchant).
 * @param {string} customerId - The customer ID.
 * @return {Promise<string | null>} - Returns the formatted phone number or null if an error occurs.
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
