import { functions, db } from "../config/main";
import * as admin from "firebase-admin";
import { FieldPath } from "firebase-admin/firestore";

type ShopOwner = {
  id: string;
  fcmToken: string;
};

/**
 * Cloud Function to remind shop owners to stay active on the platform.
 * It is triggered every 24 hours and checks for shop owners who have not
 * been active for at least a week, then sends them a reminder notification.
 */
exports.remindShopOwners = functions.pubsub
  .schedule("every 24 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    // Query for shop owners who haven't used the app in a week
    const inactiveShopOwners = await getInactiveShopOwners();

    // Send reminders to inactive shop owners
    for (const ownerId of inactiveShopOwners) {
      console.log(`Processing shop owner with ID: ${ownerId}`);
      const fcmToken = await getFcmToken(ownerId);
      if (fcmToken) {
        const payload: admin.messaging.Message = {
          notification: {
            title: "Stay Active",
            body: "You haven’t captured any transactions in a week. Keep your account updated for better customer management.",
          },
          data: {
            route: "/dashboard",
          },
          token: fcmToken,
        };
        sendNotification(payload);
      } else {
        console.log(`No FCM token found for owner ID: ${ownerId}`);
      }
    }
  });

/**
 * Fetches shop owners who have not updated their account in the last week.
 * @return {Promise<string[]>} A promise that resolves to an array of shop owner IDs.
 */
async function getInactiveShopOwners(): Promise<string[]> {
  const oneWeekAgo = new Date();
  oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);

  const shopOwnersQuerySnapshot = await db
    .collection("users")
    .where("balanceData.lastUpdated", "<=", oneWeekAgo)
    .select(FieldPath.documentId())
    .get();

  const inactiveShopOwners = shopOwnersQuerySnapshot.docs.map((doc) => doc.id);

  return inactiveShopOwners;
}

/**
 * Sends a notification to a shop owner using Firebase Cloud Messaging.
 * @param {admin.messaging.Message} payload - The notification payload to be sent.
 */
function sendNotification(payload: admin.messaging.Message): void {
  admin
    .messaging()
    .send(payload)
    .then((response) => {
      console.log("Successfully sent message:", response);
    })
    .catch((error) => {
      console.log("Error sending message:", error);
    });
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
