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
  .onCreate(async (snapshot, context) => {
    const { userId } = context.params;

    try {
      await updateBalances(userId);
      console.log(`Processed transaction for user ${userId}`);
    } catch (error) {
      console.error(`Error updating balance for mercant ${userId}:`, error);
    }
  });

/**
 * Updates the balance of a customers and merchants balance based on the new transaction.
 *
 * @param {string} userId - The ID of the user.
 * @param {string} customerId - The ID of the customer.
 */
async function updateBalances(userId: string) {
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
          .collection("transactions");
        transactionReads.push(transaction.get(transactionsRef));
      });

      // Resolving all transaction reads
      const transactionResults = await Promise.all(transactionReads);

      transactionResults.forEach((transactionsSnapshot, index) => {
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

        // Update individual customer balance
        const customerDoc = customersSnapshot.docs[index];
        transaction.set(
          customersRef.doc(customerDoc.id),
          { balance: currentCustomerBalance },
          { merge: true },
        );
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
        lastUpdated: FieldValue.serverTimestamp(),
      };

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
