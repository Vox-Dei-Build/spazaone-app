import { createHmac, timingSafeEqual } from "crypto";

/** Secret Manager/CLI inputs commonly include a terminal newline. */
export function normalizePaystackSecret(value: unknown): string {
  return String(value ?? "").trim();
}

/** Verify Paystack's SHA-512 HMAC without leaking timing information. */
export function verifyPaystackSignature(
  rawBody: Buffer,
  suppliedSignature: string | undefined,
  secret: string,
): boolean {
  if (!suppliedSignature || !/^[a-f0-9]{128}$/i.test(suppliedSignature)) {
    return false;
  }
  const expected = createHmac("sha512", secret).update(rawBody).digest("hex");
  const left = Buffer.from(suppliedSignature.toLowerCase(), "utf8");
  const right = Buffer.from(expected, "utf8");
  return left.length === right.length && timingSafeEqual(left, right);
}

export function centsFromRands(value: unknown): number {
  return Math.round(Number(value) * 100);
}
