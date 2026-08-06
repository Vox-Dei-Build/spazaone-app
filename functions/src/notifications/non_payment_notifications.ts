import { functions, db } from "../config/main";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

type ShopOwner = {
  id: string;
  fcmToken: string;
};

/**
 * Cloud Function to remind shop owners about non-paying customers.
 * It is triggered every 72 hours and checks for customers marked as non-paying (isNPA: true),
 * then sends a notification to the shop owners if they haven't been notified this month.
 */
exports.remindShopOwnersOfNonPayingCustomers = functions.pubsub
  .schedule("every 72 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    try {
      console.log("Starting to process non-paying customers...");
      const shopOwners = await getShopOwnersWithNonPayingCustomers();
      console.log(
        `Found ${shopOwners.length} shop owners with non-paying customers.`,
      );
      for (const shopOwner of shopOwners) {
        if (!(await hasBeenNotifiedRecently(shopOwner.id))) {
          await sendReminderToShopOwner(shopOwner);
          await markAsNotified(shopOwner.id);
        }
      }
    } catch (error) {
      console.error("Error processing non-paying customers:", error);
    }
  });

/**
 * Fetches shop owners who have non-paying customers.
 * @return {Promise<ShopOwner[]>} A promise that resolves to an array of shop owner objects.
 */
async function getShopOwnersWithNonPayingCustomers() {
  try {
    console.log("Fetching shop owners with non-paying customers...");
    const shopOwners = [];
    const snapshot = await admin
      .firestore()
      .collectionGroup("customers") // Assuming 'customers' is a sub-collection under each 'shopOwner'
      .where("isNPA", "==", true)
      .get();

    for (const doc of snapshot.docs) {
      const shopOwnerRef = doc.ref.parent.parent; // Reference to the shop owner document
      if (shopOwnerRef) {
        const fcmToken = await getFcmToken(shopOwnerRef.id);
        if (fcmToken) {
          shopOwners.push({ id: shopOwnerRef.id, fcmToken });
        }
      }
    }

    return shopOwners;
  } catch (error) {
    console.error("Error fetching shop owners:", error);
    return []; // Return an empty array in case of error
  }
}

/**
 * Sends a notification to a shop owner about their non-paying customers.
 * @param {ShopOwner} shopOwner - The shop owner object.
 */
async function sendReminderToShopOwner(shopOwner: ShopOwner) {
  try {
    console.log(`Sending reminder to shop owner: ${shopOwner.id}`);
    const payload = {
      notification: {
        title: "Payment Reminder",
        body: "You have customers who have not completed their payments. Please review your ledger.",
      },
      data: {
        route: "/dashboard",
        action: "SHOW_NON_PAYING_CUSTOMERS",
      },
      token: shopOwner.fcmToken,
    };

    await admin.messaging().send(payload);
    console.log(`Notification sent to shop owner ${shopOwner.id}`);
  } catch (error) {
    console.error(
      `Error sending notification to shop owner ${shopOwner.id}: `,
      error,
    );
  }
}

/**
 * Marks a shop owner as having been notified, setting the current date.
 * @param {string} shopOwnerId - The ID of the shop owner.
 */
async function markAsNotified(shopOwnerId: string) {
  try {
    console.log(`Marking shop owner ${shopOwnerId} as notified.`);
    const lastNotifiedDate = new Date();
    // Reference to the user's notifications subcollection
    const userNotificationsRef = admin
      .firestore()
      .collection("users")
      .doc(shopOwnerId)
      .collection("notifications");

    // You can create a document with a specific ID or use .add() to auto-generate an ID
    await userNotificationsRef.doc().set(
      {
        lastNotifiedDate: lastNotifiedDate,
      },
      { merge: true },
    );

    console.log(`Shop owner ${shopOwnerId} marked as notified.`);
  } catch (error) {
    console.error(
      `Error marking shop owner ${shopOwnerId} as notified: `,
      error,
    );
  }
}

/**
 * Checks if a shop owner has been notified within the last 3 days.
 * @param {string} shopOwnerId - The ID of the shop owner.
 * @return {Promise<boolean>} A promise that resolves to a boolean indicating if the owner has been notified within the period.
 */
async function hasBeenNotifiedRecently(shopOwnerId: string) {
  try {
    const lastNotificationDoc = await admin
      .firestore()
      .collection("users")
      .doc(shopOwnerId)
      .collection("notifications")
      .doc()
      .get();

    const data = lastNotificationDoc.data();
    const threeDaysAgo = new Date();
    threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);

    // Check if the last notified date is within the last three days
    return data && new Date(data.lastNotifiedDate.toDate()) >= threeDaysAgo;
  } catch (error: any) {
    const errorCode = error.errorInfo.code;
    if (errorCode === "messaging/registration-token-not-registered") {
      console.log(
        `FCM token for shop owner ${shopOwnerId} is not registered. Removing token.`,
      );
      await removeInvalidToken(shopOwnerId);
    } else {
      // Handle other errors
      console.error(
        `Error sending notification to shop owner ${shopOwnerId}:`,
        error,
      );
    }

    return [];
  }
}

/**
 * Retrieves the Firebase Cloud Messaging token for a given shop owner ID.
 * @param {string} ownerId - The ID of the shop owner.
 * @return {Promise<string | null>} A promise that resolves to the FCM token or null if not found.
 */
async function getFcmToken(ownerId: string): Promise<string | null> {
  const ownerDoc = await db.collection("users").doc(ownerId).get();
  if (!ownerDoc.exists) {
    console.log(`No document found for owner ID: ${ownerId}`);
    return null;
  }
  const ownerData = ownerDoc.data() as ShopOwner;
  return ownerData.fcmToken || null;
}

/**
 * Removes the invalid FCM token for a shop owner from the database.
 * @param {string} shopOwnerId - The ID of the shop owner whose token should be removed.
 */
async function removeInvalidToken(shopOwnerId: string) {
  try {
    console.log(`Removing invalid FCM token for shop owner: ${shopOwnerId}`);
    const shopOwnerRef = admin
      .firestore()
      .collection("shopOwners")
      .doc(shopOwnerId);
    await shopOwnerRef.update({
      fcmToken: FieldValue.delete(),
    });
    console.log(`Invalid FCM token removed for shop owner: ${shopOwnerId}`);
  } catch (error) {
    console.error(
      `Error removing invalid FCM token for shop owner ${shopOwnerId}:`,
      error,
    );
  }
}
