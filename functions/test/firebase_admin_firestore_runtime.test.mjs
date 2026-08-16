import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import test from "node:test";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const functionsRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const sourceRoot = path.join(functionsRoot, "src");

function TypeScriptFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) return TypeScriptFiles(absolute);
    return entry.isFile() && entry.name.endsWith(".ts") ? [absolute] : [];
  });
}

test("firebase-admin modular Firestore runtime exports are callable", () => {
  const {
    FieldPath,
    FieldValue,
    GeoPoint,
    Timestamp,
  } = require("firebase-admin/firestore");

  assert.equal(typeof FieldValue?.serverTimestamp, "function");
  assert.equal(typeof Timestamp?.now, "function");
  assert.equal(typeof FieldPath?.documentId, "function");
  assert.equal(typeof GeoPoint, "function");

  const sentinels = [
    FieldValue.serverTimestamp(),
    FieldValue.delete(),
    FieldValue.increment(1),
    FieldValue.arrayUnion("value"),
    FieldValue.arrayRemove("value"),
  ];
  for (const sentinel of sentinels) {
    assert.ok(sentinel instanceof FieldValue);
  }

  assert.ok(Timestamp.now() instanceof Timestamp);
  assert.ok(Timestamp.fromMillis(0) instanceof Timestamp);
  assert.ok(FieldPath.documentId() instanceof FieldPath);
  assert.ok(new GeoPoint(-33.9249, 18.4241) instanceof GeoPoint);
});

test("Functions source never resolves Firestore runtime values via Admin namespaces", () => {
  const forbidden =
    /\b(?:admin\.)?firestore\.(?:FieldValue|Timestamp|FieldPath|GeoPoint)\b/g;
  const violations = [];

  for (const file of TypeScriptFiles(sourceRoot)) {
    const source = fs.readFileSync(file, "utf8");
    const matches = [...source.matchAll(forbidden)];
    for (const match of matches) {
      const line = source.slice(0, match.index).split("\n").length;
      violations.push(`${path.relative(functionsRoot, file)}:${line}`);
    }
  }

  assert.deepEqual(
    violations,
    [],
    `Use named runtime imports from firebase-admin/firestore: ${violations.join(
      ", ",
    )}`,
  );
});

test("merchant ordering link build uses the modular Firestore entrypoint", () => {
  const compiled = fs.readFileSync(
    path.join(functionsRoot, "lib/ecommerce/getMerchantOrderingLink.js"),
    "utf8",
  );

  assert.match(compiled, /require\("firebase-admin\/firestore"\)/);
  assert.doesNotMatch(compiled, /firebase-admin"\).*\.firestore\.FieldValue/s);
});

test("merchant ordering number accepts the Functions environment", () => {
  const previous = process.env.ORDERING_WHATSAPP_NUMBER;
  process.env.ORDERING_WHATSAPP_NUMBER = "+27600000000";
  try {
    const {
      configuredPasellaWhatsappNumber,
    } = require("../lib/ecommerce/getMerchantOrderingLink");
    assert.equal(configuredPasellaWhatsappNumber(), "+27600000000");
  } finally {
    if (previous == null) {
      delete process.env.ORDERING_WHATSAPP_NUMBER;
    } else {
      process.env.ORDERING_WHATSAPP_NUMBER = previous;
    }
  }
});

test("merchant ordering number does not fall back to Twilio", () => {
  const previousOrdering = process.env.ORDERING_WHATSAPP_NUMBER;
  const previousTwilio = process.env.TWILIO_NUMBER;
  delete process.env.ORDERING_WHATSAPP_NUMBER;
  process.env.TWILIO_NUMBER = "+27609999999";
  try {
    const {
      configuredPasellaWhatsappNumber,
    } = require("../lib/ecommerce/getMerchantOrderingLink");
    assert.equal(configuredPasellaWhatsappNumber(), "");
  } finally {
    if (previousOrdering == null) {
      delete process.env.ORDERING_WHATSAPP_NUMBER;
    } else {
      process.env.ORDERING_WHATSAPP_NUMBER = previousOrdering;
    }
    if (previousTwilio == null) {
      delete process.env.TWILIO_NUMBER;
    } else {
      process.env.TWILIO_NUMBER = previousTwilio;
    }
  }
});
