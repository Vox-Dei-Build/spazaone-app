import assert from "node:assert/strict";
import test from "node:test";

import {
  prepareProductionRemoteConfig,
  RELEASE_BUILD,
  RELEASE_VERSION,
} from "../scripts/prepare-production-remote-config.mjs";

test("current release presentation flags preserve production defaults and config", () => {
  const source = {
    parameters: {
      FEATURE_MULTI_STORE_OPERATORS_ENABLED: {
        defaultValue: { value: "true" },
      },
    },
    parameterGroups: {
      "Feature Flags": {
        parameters: {
          FEATURE_TOP_UP_PAYSTACK_ENABLED: {
            defaultValue: { value: "false" },
            conditionalValues: {
              existing_release_condition: { value: "false" },
            },
          },
        },
      },
      Existing: {
        parameters: { KEEP_ME: { defaultValue: { value: "yes" } } },
      },
    },
  };

  const candidate = prepareProductionRemoteConfig(source);
  const flags = candidate.parameterGroups["Feature Flags"].parameters;

  assert.deepEqual(source.parameterGroups.Existing, {
    parameters: { KEEP_ME: { defaultValue: { value: "yes" } } },
  });
  assert.deepEqual(
    candidate.parameterGroups.Existing,
    source.parameterGroups.Existing,
  );
  assert.equal(
    candidate.parameters.FEATURE_MULTI_STORE_OPERATORS_ENABLED.defaultValue
      .value,
    "true",
  );
  assert.equal(flags.FEATURE_ONLINE_SALES_ENABLED.defaultValue.value, "false");
  assert.equal(
    flags.FEATURE_TOP_UP_PAYSTACK_ENABLED.defaultValue.value,
    "false",
  );
  assert.equal(
    flags.FEATURE_TOP_UP_PAYSTACK_ENABLED.conditionalValues
      .existing_release_condition.value,
    "false",
  );
  assert.equal(
    flags.FEATURE_ONLINE_SALES_ENABLED.conditionalValues
      [`spazaone_${RELEASE_VERSION.replaceAll(".", "")}_android_build_${RELEASE_BUILD}`]
      .value,
    "true",
  );
  assert.equal(
    flags.FEATURE_ONLINE_SALES_ENABLED.conditionalValues
      [`spazaone_${RELEASE_VERSION.replaceAll(".", "")}_ios_build_${RELEASE_BUILD}`]
      .value,
    "true",
  );
  assert.match(
    candidate.conditions[0].expression,
    new RegExp(`app\\.build\\.exactlyMatches\\(\\['${RELEASE_BUILD}'\\]\\)`),
  );
  assert.match(
    candidate.conditions[1].expression,
    new RegExp(`app\\.build\\.exactlyMatches\\(\\['${RELEASE_BUILD}'\\]\\)`),
  );
});

test("preparation is idempotent and never adds a payment-authority flag", () => {
  const once = prepareProductionRemoteConfig({
    parameters: {},
    parameterGroups: {},
    conditions: [],
  });
  const twice = prepareProductionRemoteConfig(once);

  assert.deepEqual(twice, once);
  assert.equal(twice.conditions.length, 2);
  const serialized = JSON.stringify(twice);
  assert.equal(serialized.includes("PAYMENTS_V2_MASTER_ENABLED"), false);
  assert.equal(serialized.includes("COMMERCE_PAYMENTS_ENABLED"), false);
});
