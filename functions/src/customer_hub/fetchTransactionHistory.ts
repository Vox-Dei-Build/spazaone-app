/**
 * HTTP Function to fetch the transaction history for a user.
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 */
import { functions, db } from "../config/main";
import { normalizePhoneNumber } from "../contact/fetchUserBalance";
import { requireBotRequest } from "../security/requestAuth";

/**
 * HTTP GET Function to fetch the transaction history for a user.
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 * @return {Promise<void>} - Sends the transaction history as an HTTP response.
 */
exports.fetchTransactionHistoryOption = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    const rawNumber = req.query.number as string; // Get phone number from query params

    if (!rawNumber) {
      res.status(400).send("The phone number must be provided.");
      return;
    }

    const normalizedNumber = normalizePhoneNumber(
      rawNumber.replace("whatsapp:", ""),
    );
    console.log(`Normalized number: ${normalizedNumber}`);

    const now = new Date();
    const lastMonth = new Date(now.setMonth(now.getMonth() - 1));

    try {
      const customersRef = db.collectionGroup("customers");
      const querySnapshot = await customersRef
        .where("number", "==", normalizedNumber)
        .get();

      if (querySnapshot.empty) {
        res.status(404).send("No customers found with this number.");
      }

      const allTransactions: string[] = [];

      const transactionPromises = querySnapshot.docs.map(
        async (customerDoc: any) => {
          const transactionsRef = customerDoc.ref.collection("transactions");
          const transactionsSnapshot = await transactionsRef
            .orderBy("date", "desc")
            .where("date", ">=", lastMonth)
            .get();

          if (transactionsSnapshot.empty) {
            console.log(
              `No transactions found for customer ID: ${customerDoc.id}`,
            );
            return;
          }

          const transactionDetails = await Promise.all(
            transactionsSnapshot.docs.map(async (doc: any) => {
              const transaction = doc.data();
              const amount = transaction.amount.toFixed(2);
              const date = transaction.date
                .toDate()
                .toISOString()
                .split("T")[0];
              const type = transaction.type === "Credit" ? "-" : "+";

              let productDetails = "";
              if (transaction.products) {
                const pathSegments = customerDoc.ref.path.split("/");
                const userId = pathSegments[1];

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
                      return `${productData?.name}: R${productData?.sellingPrice.toFixed(2)}\n`;
                    } else {
                      return "";
                    }
                  },
                );
                const products = await Promise.all(productPromises);
                productDetails = products.filter(Boolean).join("* ");
              }

              return productDetails
                ? `\nTransaction: ${type}R${amount} on ${date} for Products: \n${`* ${productDetails}\n`}`
                : `\nTransaction: ${type}R${amount} on ${date} (No products associated) \n`;
            }),
          );

          const pathSegments = customerDoc.ref.path.split("/");
          const userId = pathSegments[1];
          const userRef = db.collection("users").doc(userId);
          const userDoc = await userRef.get();
          const shopName = userDoc.exists
            ? userDoc.data()?.shopName || "Unknown Shop"
            : "Unknown Shop";
          const merchantName = userDoc.exists
            ? userDoc.data()?.name || "Unknown Shop Owner"
            : "Unknown Shop Owner";

          allTransactions.push(
            `📜 Your recent transactions with ${merchantName} at ${shopName}:\n` +
              transactionDetails.join("\n"),
          );
        },
      );

      await Promise.all(transactionPromises);

      if (allTransactions.length === 0) {
        res.status(404).send("No recent transactions found.");
        return;
      }

      let transactionHistory = allTransactions.join("\n");
      if (transactionHistory.length > 1000) {
        transactionHistory = transactionHistory.substring(0, 1000) + "...";
      }

      console.log(
        `Transaction history for ${normalizedNumber}:\n${transactionHistory}`,
      );
      res.status(200).send({ message: transactionHistory });
    } catch (error) {
      console.error("Failed to fetch transaction history:", error);
      res.status(500).send("Failed to fetch transaction history.");
    }
  });
