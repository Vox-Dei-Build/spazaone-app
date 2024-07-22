import * as admin from "firebase-admin";

admin.initializeApp();
export const db = admin.firestore();
export * as functions from "firebase-functions";
