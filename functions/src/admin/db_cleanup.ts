import { functions, db } from "../config/main";

/**
 * Normalizes a phone number to a standard local format without country code.
 *
 * @param {string} rawNumber - The raw phone number.
 * @return {string} - The normalized phone number in local format, e.g., 0648370009.
 */
function normalizePhoneNumber(rawNumber: string) {
  console.log(`Normalizing number: ${rawNumber}`);

  if (rawNumber === "") {
    console.log("Received empty string, leaving as is.");
    return rawNumber; // Return the empty string unchanged
  }

  let digits = rawNumber.replace(/\D/g, ""); // Remove all non-digit characters

  // Remove country code if present
  if (digits.startsWith("27")) {
    digits = "0" + digits.substring(2);
  } else if (!digits.startsWith("0")) {
    digits = "0" + digits.substring(digits.length - 9);
  }

  console.log(`Normalized to local format: ${digits}`);
  return digits;
}

/**
 * Function to normalize and update all customer phone numbers in the database.
 */
exports.normalizeAndUpdatePhoneNumbers = functions.https.onCall(
  async (data, context) => {
    // Ensure the user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Authentication is required to execute this function.",
      );
    }

    const customersRef = db.collectionGroup("customers");
    const snapshot = await customersRef.get();

    if (snapshot.empty) {
      console.log("No customer records found.");
      return { message: "No customer records found." };
    }

    // Prepare to update phone numbers in batch to minimize transaction costs and manage execution limits
    let batch = db.batch();
    let count = 0;

    snapshot.forEach((doc) => {
      const customer = doc.data();
      const normalizedNumber = normalizePhoneNumber(customer.number);

      // Enhanced logging for detailed tracking
      console.log(
        `Customer ID: ${doc.id}, Original: ${customer.number}, Normalized: ${normalizedNumber}`,
      );

      // Add to batch
      batch.update(doc.ref, { number: normalizedNumber });
      count++;

      // Commit in batches of 500 to stay within limits
      if (count >= 500) {
        batch
          .commit()
          .then(() =>
            console.log("Batch of 500 updates successfully committed."),
          );
        batch = db.batch();
        count = 0;
      }
    });

    // Commit any remaining changes
    if (count > 0) {
      await batch
        .commit()
        .then(() => console.log("Final batch update successfully committed."));
    }

    console.log(`Updated phone numbers for ${snapshot.size} customers.`);
    return {
      message: `Successfully updated phone numbers for ${snapshot.size} customers.`,
    };
  },
);
