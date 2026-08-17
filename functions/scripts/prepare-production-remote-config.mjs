#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const RELEASE_BUILD = 88;
const ANDROID_APP_ID = "1:716158514645:android:a4f2b4756aafcebbe5795c";
const IOS_APP_ID = "1:716158514645:ios:17eba128d70a92a7e5795c";

const RELEASE_CONDITIONS = [
  {
    name: "spazaone_480_android_build_88",
    expression:
      `app.id == '${ANDROID_APP_ID}' && ` +
      `app.build.exactlyMatches(['${RELEASE_BUILD}'])`,
    tagColor: "BLUE",
  },
  {
    name: "spazaone_480_ios_build_88",
    expression:
      `app.id == '${IOS_APP_ID}' && ` +
      `app.build.exactlyMatches(['${RELEASE_BUILD}'])`,
    tagColor: "INDIGO",
  },
];

const RELEASE_PRESENTATION_FLAGS = [
  "FEATURE_ONLINE_SALES_ENABLED",
  "FEATURE_TOP_UP_PAYSTACK_ENABLED",
  "FEATURE_OWNED_ORDER_PAYMENTS_ENABLED",
  "FEATURE_ACCOUNT_SETTLEMENT_PAYMENTS_ENABLED",
  "FEATURE_CUSTOMER_PAYMENT_REQUESTS_ENABLED",
  "FEATURE_SUPPLIER_ORDER_PAYMENTS_ENABLED",
];

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!new Set(["--source", "--output"]).has(argument)) {
      throw new Error(`Unexpected argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${argument}`);
    }
    values[argument.slice(2)] = path.resolve(value);
    index += 1;
  }
  if (!values.source || !values.output) {
    throw new Error(
      "Usage: --source CURRENT_TEMPLATE --output CANDIDATE_TEMPLATE",
    );
  }
  if (values.source === values.output) {
    throw new Error("Source and output must be different files.");
  }
  return values;
}

function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object.`);
  }
  return value;
}

export function prepareProductionRemoteConfig(template) {
  const candidate = structuredClone(object(template, "Remote Config template"));
  candidate.parameters = object(candidate.parameters ?? {}, "parameters");
  candidate.parameterGroups = object(
    candidate.parameterGroups ?? {},
    "parameterGroups",
  );

  const existingConditions = Array.isArray(candidate.conditions)
    ? candidate.conditions.filter(
        (condition) =>
          !RELEASE_CONDITIONS.some(
            (release) => release.name === condition?.name,
          ),
      )
    : [];
  candidate.conditions = [...RELEASE_CONDITIONS, ...existingConditions];

  const featureGroup = object(
    candidate.parameterGroups["Feature Flags"] ?? { parameters: {} },
    "Feature Flags group",
  );
  featureGroup.parameters = object(
    featureGroup.parameters ?? {},
    "Feature Flags parameters",
  );
  candidate.parameterGroups["Feature Flags"] = featureGroup;

  for (const key of RELEASE_PRESENTATION_FLAGS) {
    const existing = object(
      featureGroup.parameters[key] ?? {},
      `${key} parameter`,
    );
    const existingConditionalValues = object(
      existing.conditionalValues ?? {},
      `${key} conditional values`,
    );
    featureGroup.parameters[key] = {
      ...existing,
      defaultValue: { value: "false" },
      conditionalValues: {
        ...existingConditionalValues,
        ...Object.fromEntries(
          RELEASE_CONDITIONS.map((condition) => [
            condition.name,
            { value: "true" },
          ]),
        ),
      },
      description:
        "Enabled only for Spaza One 4.8.0+88 internal/release QA. " +
        "Server payment authority remains independently fail-closed.",
      valueType: "BOOLEAN",
    };
  }

  candidate.version = {
    ...(candidate.version ?? {}),
    description:
      "Spaza One 4.8.0+88 build-scoped presentation gates; payments remain server-dark",
  };
  return candidate;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const source = JSON.parse(fs.readFileSync(args.source, "utf8"));
  const candidate = prepareProductionRemoteConfig(source);
  fs.writeFileSync(args.output, `${JSON.stringify(candidate, null, 2)}\n`, {
    flag: "wx",
  });
  process.stdout.write(
    `${JSON.stringify({
      status: "prepared",
      output: args.output,
      releaseBuild: RELEASE_BUILD,
      conditions: RELEASE_CONDITIONS.map(({ name }) => name),
      presentationFlags: RELEASE_PRESENTATION_FLAGS,
      serverPaymentGatesChanged: false,
    })}\n`,
  );
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) ===
    path.resolve(new URL(import.meta.url).pathname)
) {
  main();
}
