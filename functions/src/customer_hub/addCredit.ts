import { Timestamp } from "firebase-admin/firestore";
import { functions, db } from "../config/main";

/**
 * Cloud Function to add a credit transaction for a customer.
 *
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 */
exports.addCreditTransaction = functions.https.onRequest(async (req, res) => {
  // Set repayment date to a month from now
  const defaultSelectedDate = Timestamp.now(); // Use Firestore Timestamp for current date
  const defaultRepaymentDate = new Date();
  defaultRepaymentDate.setMonth(defaultRepaymentDate.getMonth() + 1); // Add 1 month
  const repaymentDateTimestamp = Timestamp.fromDate(defaultRepaymentDate);

  const {
    userId,
    customerId,
    amount,
    selectedDate = defaultSelectedDate,
    repaymentDate = repaymentDateTimestamp,
    remarks,
    selectedProducts,
    customerName,
    mobileNumber,
  } = req.body;

  if (!userId || !customerId || !amount || !customerName || !mobileNumber) {
    res.status(400).json({ error: "Missing required fields." });
    return;
  }

  try {
    // Validate amount
    let amountEntered = parseFloat(amount);
    if (isNaN(amountEntered) || amountEntered <= 0) {
      res.status(400).json({ error: "Invalid amount entered." });
      return;
    }

    if (Number.isInteger(amount)) {
      amountEntered = amount + 0.0000001; // Small decimal to force Firestore to store it as a double: https://github.com/firebase/flutterfire/issues/9626
    }

    // Create the transaction data object
    const transactionData = {
      type: "Credit",
      amount: amountEntered,
      date: selectedDate,
      repaymentDate: repaymentDate,
      remarks: remarks || "",
      status: "DUE",
      // products: selectedProducts,
    };

    // Add transaction to Firestore
    await db
      .collection("users")
      .doc(userId)
      .collection("customers")
      .doc(customerId)
      .collection("transactions")
      .add(transactionData);

    if (selectedProducts != null) {
      // Update product quantities in Firestore
      const productUpdatePromises = Object.keys(selectedProducts).map(
        async (productId) => {
          const productDoc = await db
            .collection("users")
            .doc(userId)
            .collection("products")
            .doc(productId)
            .get();
          if (productDoc.exists) {
            const productData = productDoc.data();
            const newQuantity =
              (productData?.quantity || 0) - selectedProducts[productId];
            await db
              .collection("users")
              .doc(userId)
              .collection("products")
              .doc(productId)
              .update({
                quantity: newQuantity,
              });
          }
        },
      );

      await Promise.all(productUpdatePromises);
    }

    // Update the 'lastTransaction' field in the customer document
    const customerRef = db
      .collection("users")
      .doc(userId)
      .collection("customers")
      .doc(customerId);
    await customerRef.update({
      lastTransaction: transactionData,
    });

    // Send success response
    res.status(200).json({ message: "Credit transaction added successfully!" });
  } catch (error) {
    console.error("Error adding credit transaction:", error);
    res
      .status(500)
      .json({ error: "Error adding credit transaction. Please try again." });
  }
});
