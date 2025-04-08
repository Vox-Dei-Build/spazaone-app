import { functions, db } from "../config/main";
import { AndroidConfig } from "firebase-admin/messaging";
import * as admin from "firebase-admin";

/**
 * Cloud Function: Log unread message & trigger push notification
 *
 * @param {functions.https.Request} req - The HTTP request object from Twilio, containing status information.
 * @param {functions.Response} res - The HTTP response object to send back to Twilio.
 */
export const logUnreadMessage = functions.https.onRequest(async (req, res) => {
  try {
    const { merchantId, customerNumber, message } = req.body;

    if (!merchantId || !customerNumber || !message) {
      res.status(400).json({ error: "Missing required fields" });
      return; // ✅ Ensure function stops execution
    }

    // Reference to merchant document in Firestore
    const merchantRef = db.collection("users").doc(merchantId);

    // Get existing unread count and messages
    const merchantDoc = await merchantRef.get();
    let unreadCount = 0;
    let unreadMessages = [];

    if (merchantDoc.exists) {
      const data = merchantDoc.data();
      unreadMessages = data?.unreadMessages || [];
      unreadCount = data?.unreadCount || 0;
    }

    // ✅ Generate timestamp first
    const timestamp = new Date(); // ✅ Use JavaScript Date instead of Firestore serverTimestamp

    // ✅ Append the new message with a normal timestamp
    unreadMessages.push({
      customerNumber,
      message,
      timestamp: timestamp.toISOString(), // 🔥 Convert timestamp to a string format
    });

    // ✅ Update Firestore with new unread messages and increment count
    await merchantRef.set(
      {
        unreadMessages: unreadMessages,
        unreadCount: unreadCount + 1,
      },
      { merge: true },
    );

    // Fetch merchant FCM token from Firestore
    const merchantData = await merchantRef.get();
    const merchantFCMToken = merchantData.data()?.fcmToken;
    console.log(merchantFCMToken);

    if (!merchantFCMToken) {
      console.log("Merchant FCM Token not found.");
      res
        .status(200)
        .json({ message: "Unread message logged, but no FCM token." });
      return;
    }

    const androidConfig: AndroidConfig = {
      priority: "high",
      notification: {
        channelId: "default_channel", // ✅ Correct key for channel ID
        sound: "default",
      },
    };

    // ✅ Send push notification via Firebase Cloud Messaging
    const payload = {
      notification: {
        title: "New Customer Message 📩",
        body: "You have a new message from a customer.",
      },
      android: androidConfig,
      data: {
        unreadCount: (unreadCount + 1).toString(),
      },
      token: merchantFCMToken,
    };

    console.log("Sending FCM notification:", payload);

    try {
      const response = await admin.messaging().send(payload);
      console.log("✅ Push notification sent successfully:", response);
    } catch (error) {
      console.error("❌ Error sending push notification:", error);
    }

    res
      .status(200)
      .json({ message: "Unread message logged & notification sent." });
  } catch (error) {
    console.error("Error logging unread message:", error);
    res.status(500).json({ error: "Internal Server Error" });
  }
});
