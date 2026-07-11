import * as admin from "firebase-admin";
import { timingSafeEqual } from "crypto";
import { functions } from "../config/main";

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
  if (!provided || !expected) return false;
  const left = Buffer.from(provided);
  const right = Buffer.from(expected);
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

export const authorizeCallableMerchantOrBot = (
  context: functions.https.CallableContext,
  merchantId: string,
): boolean =>
  context.auth?.uid === merchantId || verifyBotRequest(context.rawRequest);
