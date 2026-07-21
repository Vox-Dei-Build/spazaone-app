import * as admin from "firebase-admin";
import { timingSafeEqual } from "crypto";
import { db, functions } from "../config/main";

type HttpRequest = functions.https.Request;
type HttpResponse = functions.Response;

const bearerToken = (authorization: string | undefined): string | null => {
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
};

const safeSecretEquals = (
  provided: string | undefined,
  expected: string | undefined,
): boolean => {
  const normalizedProvided = provided?.trim();
  const normalizedExpected = expected?.trim();
  if (!normalizedProvided || !normalizedExpected) return false;
  const left = Buffer.from(normalizedProvided);
  const right = Buffer.from(normalizedExpected);
  return left.length === right.length && timingSafeEqual(left, right);
};

export const verifyBotRequest = (req: HttpRequest): boolean =>
  safeSecretEquals(
    req.get("X-Pasella-Bot-Token"),
    process.env.PASELLA_BOT_TOKEN,
  );

export const requireBotRequest = (
  req: HttpRequest,
  res: HttpResponse,
): boolean => {
  if (verifyBotRequest(req)) return true;
  console.warn("[requestAuth] rejected unauthenticated bot request", {
    function: req.path,
  });
  res.status(401).json({ error: "Authentication required." });
  return false;
};

export const authenticateFirebaseRequest = async (
  req: HttpRequest,
  res: HttpResponse,
  options: {
    expectedUid?: string;
    requireAppCheck?: boolean;
  } = {},
): Promise<string | null> => {
  const token = bearerToken(req.get("Authorization"));
  if (!token) {
    res.status(401).json({ error: "Authentication required." });
    return null;
  }

  let uid: string;
  try {
    uid = (await admin.auth().verifyIdToken(token)).uid;
  } catch (error) {
    console.warn("[requestAuth] invalid Firebase ID token");
    res.status(401).json({ error: "Authentication required." });
    return null;
  }

  if (options.expectedUid && uid !== options.expectedUid) {
    res.status(403).json({ error: "Access denied." });
    return null;
  }

  const appCheckToken = req.get("X-Firebase-AppCheck");
  if (appCheckToken) {
    try {
      await admin.appCheck().verifyToken(appCheckToken);
    } catch (error) {
      console.warn("[requestAuth] invalid App Check token", { uid });
      res.status(401).json({ error: "App verification failed." });
      return null;
    }
  } else if (options.requireAppCheck) {
    res.status(401).json({ error: "App verification required." });
    return null;
  }

  return uid;
};

export const authorizeCallableMerchantOrBot = async (
  context: functions.https.CallableContext,
  merchantId: string,
): Promise<boolean> => {
  if (verifyBotRequest(context.rawRequest)) return true;
  const uid = context.auth?.uid;
  if (!uid) return false;

  // Legacy releases use the auth uid as the merchant/store id.
  if (uid === merchantId) return true;

  const membership = await db
    .doc(`stores/${merchantId}/operators/${uid}`)
    .get();
  const role = membership.data()?.role;
  return (
    membership.exists &&
    membership.data()?.status === "active" &&
    ["owner", "admin", "operator"].includes(role)
  );
};
