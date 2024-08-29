import { functions, db } from "../config/main";

interface MerchantDetails {
  name: string;
  shopName: string;
  balance: number;
}

/**
 * Normalizes a phone number to a standard local format without country code.
 *
 * @param {string} rawNumber - The raw phone number.
 * @return {string} - The normalized phone number in local format, e.g., 0648370009.
 */
function normalizePhoneNumber(rawNumber: string) {
  if (rawNumber === "") {
    return rawNumber; // Return the empty string unchanged
  }

  let digits = rawNumber.replace(/\D/g, ""); // Remove all non-digit characters

  // Remove country code if present
  if (digits.startsWith("27")) {
    digits = "0" + digits.substring(2);
  } else if (!digits.startsWith("0")) {
    digits = "0" + digits.substring(digits.length - 9);
  }

  return digits;
}

/**
 * Fetches the user balance from the database using a stripped phone number.
 *
 * @param {string} number - The user's phone number received from WhatsApp.
 * @return {Promise<string>} - A promise resolving to a message about the user's balance.
 */
export async function fetchUserBalance(number: string): Promise<string> {
  const rawNumber = number;
  if (!rawNumber) {
    console.error("No phone number provided in the request.");
    throw new functions.https.HttpsError(
      "invalid-argument",
      "The phone number must be provided.",
    );
  }

  const normalizedNumber = normalizePhoneNumber(
    rawNumber.replace("whatsapp:", ""),
  );
  console.log(`Normalized incoming number for matching: ${normalizedNumber}`);

  try {
    // Use a collection group query to search across all 'customers' collections
    const customersRef = db.collectionGroup("customers");

    const querySnapshot = await customersRef
      .where("number", "==", normalizedNumber)
      .get();

    if (querySnapshot.empty) {
      return "No account found for this number.";
    }

    let totalBalance = 0;
    const merchantBalances: Record<string, MerchantDetails> = {};

    // Process each customer found
    const promises = querySnapshot.docs.map(async (doc) => {
      const customer = doc.data();
      console.log(
        `Customer found: ${doc.id} with balance: ${customer.balance}`,
      );
      totalBalance += customer.balance;

      const pathSegments = doc.ref.path.split("/");
      const userId = pathSegments[1]; // Fetch the user ID from the path
      console.log(`User ID: ${userId}`);

      // Fetch merchant details
      const userRef = db.collection("users").doc(userId);
      const userDoc = await userRef.get();
      const user = userDoc.data();
      const name = user?.name || "Unknown";
      const shopName = user?.shopName || "Unknown Shop";

      // Combine balances per merchant
      if (!merchantBalances[userId]) {
        merchantBalances[userId] = {
          name: name,
          shopName: shopName,
          balance: 0,
        };
      }
      merchantBalances[userId].balance += customer.balance;
    });

    // Wait for all promises to resolve
    await Promise.all(promises);

    // Construct the final message
    let message = "Your balance summary:\n";
    for (const userId in merchantBalances) {
      if (Object.prototype.hasOwnProperty.call(merchantBalances, userId)) {
        const details = merchantBalances[userId];
        message += `\nMerchant: ${details.name} (${
          details.shopName
        }) - Balance: R${details.balance.toFixed(2)}\n`;
      }
    }
    message += `\nTotal balance across all accounts: R${totalBalance.toFixed(
      2,
    )}`;

    console.log(`Final user balance response: ${message}`);
    return message;
  } catch (error) {
    console.error("Failed to fetch user balance:", error);
    return "Failed to fetch user balance";
  }
}

/**
 * Simulates fetching the transaction history for a user.
 *
 * @param {string} number - The user's identifier, from the WhatsApp message.
 * @return {Promise<string>} - A promise resolving to a formatted string of the user's recent transactions.
 */
export async function fetchTransactionHistory(number: string): Promise<string> {
  try {
    // Normalize the phone number before querying
    const normalizedNumber = normalizePhoneNumber(number);
    console.log(`Normalized number: ${normalizedNumber}`);

    // Get the current date and subtract one month to set the date range
    const now = new Date();
    const lastMonth = new Date(now.setMonth(now.getMonth() - 1));

    // Query the Firestore for the documents where the 'number' field matches the provided number
    const customersRef = db.collectionGroup("customers");
    const querySnapshot = await customersRef
      .where("number", "==", normalizedNumber)
      .get();

    if (querySnapshot.empty) {
      console.log("No customers found with this number.");
      return "No customers found with this number.";
    }

    const allTransactions: string[] = [];
    const transactionPromises = querySnapshot.docs.map(async (customerDoc) => {
      console.log(`Processing customer ID: ${customerDoc.id}`);

      const transactionsRef = customerDoc.ref.collection("transactions");
      const transactionsSnapshot = await transactionsRef
        .orderBy("date", "desc")
        .where("date", ">=", lastMonth) // Filter transactions within the last month
        .get();
      if (transactionsSnapshot.empty) {
        console.log(`No transactions found for customer ID: ${customerDoc.id}`);
        return "";
      }

      const transactionDetails = await Promise.all(
        transactionsSnapshot.docs.map(async (doc) => {
          const transaction = doc.data();
          console.log(
            `Processing transaction ID: ${doc.id} for customer ID: ${customerDoc.id}`,
          );

          const amount = transaction.amount.toFixed(2);
          const date = transaction.date.toDate().toISOString().split("T")[0];
          const type = transaction.type === "Credit" ? "-" : "+";

          // Fetch product details if any products are linked to the transaction
          let productDetails = "";
          if (transaction.products) {
            console.log(`Fetching products for transaction ID: ${doc.id}`);
            const pathSegments = customerDoc.ref.path.split("/");
            const userId = pathSegments[1]; // Fetch the user ID from the path

            const productPromises = Object.keys(transaction.products).map(
              async (productId) => {
                const productRef = db
                  .collection("users")
                  .doc(userId)
                  .collection("products")
                  .doc(productId);
                const productDoc = await productRef.get();
                if (productDoc.exists) {
                  const productData = productDoc.data();
                  console.log(
                    `Product found: ${productData?.name} with selling price: ${productData?.sellingPrice.toFixed(
                      2,
                    )}`,
                  );
                  return `${productData?.name}: R${productData?.sellingPrice.toFixed(
                    2,
                  )}\n`;
                } else {
                  console.log(
                    `Product ID: ${productId} not found in the products subcollection.`,
                  );
                  return "";
                }
              },
            );

            const products = await Promise.all(productPromises);
            productDetails = products.filter(Boolean).join("* ");
          }

          return productDetails
            ? `\nTransaction: ${type}R${amount} on ${date} for the following Products: \n${`* ${productDetails}\n`}`
            : `\nTransaction: ${type}R${amount} on ${date} (No products associated with the transaction) \n`;
        }),
      );

      // Include the merchant's shop name or user ID to distinguish transactions
      const pathSegments = customerDoc.ref.path.split("/");
      const userId = pathSegments[1];
      console.log(`User ID associated with the customer: ${userId}`);

      const userRef = db.collection("users").doc(userId);
      const userDoc = await userRef.get();
      const shopName = userDoc.exists
        ? userDoc.data()?.shopName || "Unknown Shop"
        : "Unknown Shop";

      const merchantName = userDoc.exists
        ? userDoc.data()?.name || "Unknown Shop Owner"
        : "Unknown Shop Owner";

      allTransactions.push(
        `\nTransactions with ${merchantName} (${shopName}):\n` +
          transactionDetails.join("\n"),
      );

      return ""; // Return an empty string to satisfy the return type requirement
    });

    await Promise.all(transactionPromises);

    if (allTransactions.length === 0) {
      return "No recent transactions found.";
    }

    let transactionHistory = allTransactions.join("\n");

    // Truncate the transaction history if it exceeds 1600 characters: Whatsapp Requirement
    if (transactionHistory.length > 1500) {
      transactionHistory = transactionHistory.substring(0, 1500) + "...";
    }

    console.log(
      `Transaction history for ${normalizedNumber}:\n${transactionHistory}`,
    );

    return transactionHistory;
  } catch (error) {
    console.error("Failed to fetch transaction history:", error);
    return "Failed to fetch transaction history";
  }
}
