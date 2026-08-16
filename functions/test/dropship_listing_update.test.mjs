import assert from "node:assert/strict";
import test from "node:test";

import { dropshipListingUpdate } from "../lib/commerce/updateDropshipListing.js";

test("active supplier listing recalculates price from canonical base cost", () => {
  assert.deepEqual(
    dropshipListingUpdate({
      baseCostMinor: 10_000,
      markupMinor: 2_000,
      state: "active",
      digitalPaymentsEnabled: false,
    }),
    {
      state: "active",
      markupMinor: 2_000,
      sellPriceMinor: 12_000,
      active: true,
      availability: "available",
      whatsappListed: true,
    },
  );
});

test("internal and paused supplier listings are removed from storefront", () => {
  for (const state of ["internal", "paused"]) {
    const result = dropshipListingUpdate({
      baseCostMinor: 10_000,
      markupMinor: 2_000,
      state,
      digitalPaymentsEnabled: false,
    });
    assert.equal(result.active, false);
    assert.equal(result.whatsappListed, false);
    assert.equal(result.availability, state);
  }
});

test("supplier listing update rejects invalid state and unsafe markup", () => {
  assert.throws(
    () => dropshipListingUpdate({
      baseCostMinor: 10_000,
      markupMinor: 0,
      state: "active",
      digitalPaymentsEnabled: false,
    }),
    /MARKUP_INVALID/,
  );
  assert.throws(
    () => dropshipListingUpdate({
      baseCostMinor: 10_000,
      markupMinor: 2_000,
      state: "deleted",
      digitalPaymentsEnabled: false,
    }),
    /LISTING_STATE_INVALID/,
  );
});
