import * as admin from "firebase-admin";
import { getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v1";

// ✅ Initialize Firebase Admin SDK only once
if (!admin.apps.length) {
  admin.initializeApp();
}

// ✅ Export Firestore and Messaging
export const db = getFirestore();

// ✅ Export Firebase Functions correctly
export { functions };
