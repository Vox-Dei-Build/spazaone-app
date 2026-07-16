import { functions, db } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";

/**
 * Calculates and updates the balance for a user based on transactions.
 *
 * This function performs the following operations in a Firestore transaction:
 * - Verifies user authentication.
 * - Retrieves all customers and their transactions for the authenticated user.
 * - Aggregates transaction data (payments and credits) for each customer.
 * - Updates each customer's balance and the user's overall balance data atomically.
 *
 * Firestore transaction rules are adhered to by ensuring all document reads
 * are executed before any writes. The function uses batch processing of reads
 * for efficiency.
 *
 * @param {Object} data - The data passed to the cloud function (unused in this case).
 * @param {Object} context - The context in which the function is called, contains auth data.
 * @returns {Promise<Object>} A promise that resolves with a success message and balance data upon completion.
 * @throws {functions.https.HttpsError} Throws an 'unauthenticated' error if the user is not authenticated.
 * @throws {functions.https.HttpsError} Throws an 'internal' error if the transaction fails.
 */
exports.calculateUserBalance = functions.https.onCall(async (data, context) => {
  // Check if the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated to use this function.",
    );
  }

  const userId = String(data?.storeId ?? context.auth.uid).trim();
  await assertCallableStoreAccess(context, userId);
  const startDate = data?.startDate ? new Date(data.startDate) : new Date(2000);
  const endDate = data?.endDate ? new Date(data.endDate) : new Date(); // default to now if missing

  try {
    return await db.runTransaction(async (transaction) => {
      const userRef = db.collection("users").doc(userId);
      const customersRef = userRef.collection("customers");
      const customersSnapshot = await transaction.get(customersRef);

      let totalBalance = 0;
      let paymentCount = 0;
      let paymentAmount = 0;
      let creditCount = 0;
      let creditAmount = 0;
      const totalCustomers = customersSnapshot.docs.length;
      let outstandingCustomers = 0;

      // Preparing a list of all transaction reads
      const transactionReads: Promise<FirebaseFirestore.QuerySnapshot>[] = [];
      customersSnapshot.docs.forEach((customerDoc) => {
        const transactionsRef = customersRef
          .doc(customerDoc.id)
          .collection("transactions")
          .where("date", ">=", startDate)
          .where("date", "<=", endDate);
        transactionReads.push(transaction.get(transactionsRef));
      });

      // Resolving all transaction reads
      const transactionResults = await Promise.all(transactionReads);

      transactionResults.forEach((transactionsSnapshot) => {
        let currentCustomerBalance = 0;
        transactionsSnapshot.docs.forEach((transactionDoc) => {
          const transactionData = transactionDoc.data();

          if (transactionData.type === "Credit") {
            totalBalance -= transactionData.amount;
            currentCustomerBalance -= transactionData.amount;
            creditCount++;
            creditAmount += transactionData.amount;
          } else if (transactionData.type === "Payment") {
            totalBalance += transactionData.amount;
            currentCustomerBalance += transactionData.amount;
            paymentCount++;
            paymentAmount += transactionData.amount;
          }
        });

        // Check for outstanding balance
        if (currentCustomerBalance < 0) {
          outstandingCustomers++;
        }
      });

      // Update the user's overall balance data
      const balanceData = {
        totalBalance,
        payment: {
          count: paymentCount,
          totalAmount: paymentAmount,
        },
        credit: {
          count: creditCount,
          totalAmount: creditAmount,
        },
        totalCustomers,
        outstandingCustomers,
      };

      return balanceData;
    });
  } catch (error) {
    console.error("Error in transaction:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to calculate user balance.",
    );
  }
});
