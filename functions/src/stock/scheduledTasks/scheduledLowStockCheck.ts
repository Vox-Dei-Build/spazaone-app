import { functions, db } from "../../config/main";
import * as admin from "firebase-admin";

/**
 * Scheduled function to check for low stock every 24 hours.
 *
 * @function
 * @name scheduledLowStockCheck
 * @returns {Promise<null>}
 */
exports.scheduledLowStockCheck = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async (context) => {
    const usersRef = db.collection("users");

    try {
      const usersSnapshot = await usersRef.get();
      if (usersSnapshot.empty) {
        console.log("No users found");
        return null;
      }

      usersSnapshot.forEach(async (userDoc) => {
        const userId = userDoc.id;
        const productsRef = usersRef.doc(userId).collection("products");
        const notificationsRef = usersRef
          .doc(userId)
          .collection("notifications");

        try {
          const productsSnapshot = await productsRef.get();
          if (productsSnapshot.empty) {
            console.log(`No products found for user: ${userId}`);
            return;
          }

          productsSnapshot.forEach(async (productDoc) => {
            const product = productDoc.data();
            if (product.quantity <= 5) {
              try {
                await notificationsRef.add({
                  title: "Low Stock Alert",
                  body: `${product.name} has only ${product.quantity} items left.`,
                  timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log(
                  `Notification added for product: ${product.name}, user: ${userId}`,
                );
              } catch (notificationError) {
                console.error(
                  `Error adding notification for product: ${product.name}, user: ${userId}`,
                  notificationError,
                );
              }

              try {
                await admin.messaging().send({
                  topic: userId,
                  notification: {
                    title: `Low Stock Alert for ${product.name}`,
                    body: `${product.name} has only ${product.quantity} items left.`,
                  },
                });
                console.log(
                  `FCM notification sent for product: ${product.name}, user: ${userId}`,
                );
              } catch (messagingError) {
                console.error(
                  `Error sending FCM notification for product: ${product.name}, user: ${userId}`,
                  messagingError,
                );
              }
            }
          });
        } catch (productError) {
          console.error(
            `Error retrieving products for user: ${userId}`,
            productError,
          );
        }
      });
    } catch (userError) {
      console.error("Error retrieving users", userError);
    }

    return null;
  });
