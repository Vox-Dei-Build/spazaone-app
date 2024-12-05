import { functions, db } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";

/**
 * Cloud Function triggered on transaction creation.
 * Updates the customer's balance and related data.
 */
exports.updateBalancesOnTransactionAdded = functions.firestore
  .document(
    "users/{userId}/customers/{customerId}/transactions/{transactionId}",
  )
  .onWrite(async (change, context) => {
    const { userId, customerId } = context.params;

    try {
      await updateBalancesWithEdit(userId, customerId);
      console.log(`Processed transaction for user ${userId}`);
    } catch (error) {
      console.error(`Error updating balance for mercant ${userId}:`, error);
    }
  });

/**
 * Updates the balance for a specific customer based on the new transaction.
 *
 * @param {string} userId - The ID of the user.
 * @param {string} customerId - The ID of the customer.
 */
export async function updateBalancesWithEdit(
  userId: string,
  customerId: string,
) {
  try {
    return await db.runTransaction(async (transaction) => {
      const userRef = db.collection("users").doc(userId);
      const customerRef = userRef.collection("customers").doc(customerId);
      const transactionsRef = customerRef.collection("transactions");

      // Read all transactions for the specific customer
      const transactionsSnapshot = await transaction.get(transactionsRef);

      let currentCustomerBalance = 0;
      let creditCount = 0;
      let creditAmount = 0;
      let paymentCount = 0;
      let paymentAmount = 0;

      transactionsSnapshot.docs.forEach((transactionDoc) => {
        const transactionData = transactionDoc.data();

        if (transactionData.type === "Credit") {
          currentCustomerBalance -= transactionData.amount;
          creditCount++;
          creditAmount += transactionData.amount;
        } else if (transactionData.type === "Payment") {
          currentCustomerBalance += transactionData.amount;
          paymentCount++;
          paymentAmount += transactionData.amount;
        }
      });

      // Update overall balance for the user
      const userDoc = await transaction.get(userRef);
      const balanceData = userDoc.data()?.balanceData || {
        totalBalance: 0,
        credit: { count: 0, totalAmount: 0 },
        payment: { count: 0, totalAmount: 0 },
      };

      // Update global balance data for the user
      balanceData.totalBalance =
        balanceData.totalBalance + currentCustomerBalance;
      balanceData.credit.count += creditCount;
      balanceData.credit.totalAmount += creditAmount;
      balanceData.payment.count += paymentCount;
      balanceData.payment.totalAmount += paymentAmount;
      balanceData.lastUpdated = FieldValue.serverTimestamp();

      // Update the customer's balance
      transaction.set(
        customerRef,
        { balance: currentCustomerBalance },
        { merge: true },
      );
      // Update the user's balance data
      transaction.set(userRef, { balanceData }, { merge: true });
    });
  } catch (error) {
    console.error("Error in transaction:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to calculate user balance.",
    );
  }
}
