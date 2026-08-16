#!/usr/bin/env node

import process from "node:process";
import { pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
const MERCHANT_ID = "dev-seed-merchant";
const ORDERING_CODE = "U84BCC";
const SEED_VERSION = 1;

const PRODUCTS = [
  [
    "dev-seed-owned-product",
    "Sugar 2kg",
    45,
    "bag",
    "White granulated sugar for tea, baking and everyday cooking.",
    ["2kg sugar", "sugar"],
  ],
  [
    "white-bread",
    "White Bread Loaf",
    18,
    "loaf",
    "Soft sliced white bread, ready for sandwiches and toast.",
    ["white bread"],
  ],
  [
    "brown-bread",
    "Brown Bread Loaf",
    19,
    "loaf",
    "Fresh sliced brown bread with a hearty wholewheat taste.",
    ["brown bread"],
  ],
  [
    "maize-meal-5kg",
    "Maize Meal 5kg",
    74.99,
    "bag",
    "Fortified maize meal for smooth, filling pap.",
  ],
  [
    "rice-2kg",
    "Long Grain Rice 2kg",
    54.99,
    "bag",
    "Versatile long-grain rice for family meals.",
  ],
  [
    "cake-flour-2-5kg",
    "Cake Flour 2.5kg",
    39.99,
    "bag",
    "Fine wheat flour for baking, vetkoek and sauces.",
  ],
  [
    "cooking-oil-2l",
    "Cooking Oil 2L",
    69.99,
    "bottle",
    "Refined sunflower oil for frying and everyday cooking.",
  ],
  [
    "long-life-milk-1l",
    "Long Life Milk 1L",
    19.99,
    "carton",
    "Full-cream UHT milk with a long unopened shelf life.",
  ],
  [
    "fresh-milk-2l",
    "Fresh Milk 2L",
    36.99,
    "bottle",
    "Chilled full-cream milk for cereal, tea and cooking.",
  ],
  [
    "eggs-18",
    "Large Eggs 18 Pack",
    64.99,
    "tray",
    "Eighteen large fresh eggs packed in a protective tray.",
  ],
  [
    "salt-1kg",
    "Table Salt 1kg",
    13.99,
    "bag",
    "Fine iodated table salt for seasoning and cooking.",
  ],
  [
    "baked-beans-410g",
    "Baked Beans 410g",
    16.99,
    "tin",
    "Baked beans in a rich tomato sauce.",
  ],
  [
    "pilchards-400g",
    "Pilchards in Tomato 400g",
    27.99,
    "tin",
    "Pilchards in savoury tomato sauce, ready to serve.",
  ],
  [
    "corned-meat-300g",
    "Corned Meat 300g",
    34.99,
    "tin",
    "Canned corned meat for quick sandwiches and meals.",
  ],
  [
    "peanut-butter-400g",
    "Smooth Peanut Butter 400g",
    39.99,
    "jar",
    "Smooth roasted peanut spread for bread and snacks.",
  ],
  [
    "fruit-jam-450g",
    "Mixed Fruit Jam 450g",
    29.99,
    "jar",
    "Sweet mixed-fruit jam for toast and baking.",
  ],
  [
    "rooibos-80",
    "Rooibos Tea 80 Pack",
    44.99,
    "box",
    "Naturally caffeine-free South African rooibos teabags.",
  ],
  [
    "coffee-200g",
    "Instant Coffee 200g",
    79.99,
    "jar",
    "Rich instant coffee granules for a quick hot drink.",
  ],
  [
    "black-tea-100",
    "Black Tea 100 Pack",
    49.99,
    "box",
    "Full-bodied black teabags for everyday tea.",
  ],
  [
    "oats-1kg",
    "Rolled Oats 1kg",
    42.99,
    "bag",
    "Wholegrain rolled oats for porridge and baking.",
  ],
  [
    "corn-flakes-750g",
    "Corn Flakes 750g",
    49.99,
    "box",
    "Crisp toasted corn flakes for breakfast.",
  ],
  [
    "margarine-500g",
    "Margarine 500g",
    31.99,
    "tub",
    "Everyday spread suitable for bread, cooking and baking.",
  ],
  [
    "cheddar-500g",
    "Cheddar Cheese 500g",
    89.99,
    "pack",
    "Firm cheddar cheese for sandwiches, cooking and snacks.",
  ],
  [
    "chicken-portions-2kg",
    "Chicken Portions 2kg",
    99.99,
    "bag",
    "Frozen mixed chicken portions for family meals.",
  ],
  [
    "beef-mince-1kg",
    "Beef Mince 1kg",
    109.99,
    "pack",
    "Versatile beef mince for stews, pasta and burgers.",
  ],
  [
    "boerewors-1kg",
    "Traditional Boerewors 1kg",
    119.99,
    "pack",
    "Seasoned traditional boerewors for braai or pan cooking.",
  ],
  [
    "mixed-veg-1kg",
    "Frozen Mixed Vegetables 1kg",
    39.99,
    "bag",
    "Frozen carrots, peas, corn and green beans.",
  ],
  [
    "potatoes-7kg",
    "Potatoes 7kg",
    79.99,
    "bag",
    "Versatile fresh potatoes for chips, mash and stews.",
  ],
  [
    "onions-3kg",
    "Onions 3kg",
    44.99,
    "bag",
    "Fresh brown onions for cooking and salads.",
  ],
  [
    "tomatoes-1kg",
    "Tomatoes 1kg",
    29.99,
    "bag",
    "Fresh ripe tomatoes for salads, sandwiches and cooking.",
  ],
  [
    "bananas-1kg",
    "Bananas 1kg",
    24.99,
    "bunch",
    "Fresh bananas, ideal for lunchboxes and snacks.",
  ],
  [
    "apples-1-5kg",
    "Apples 1.5kg",
    39.99,
    "bag",
    "Crisp fresh apples in a convenient family bag.",
  ],
  [
    "cabbage",
    "Cabbage Each",
    19.99,
    "each",
    "One fresh green cabbage for salads and cooked meals.",
  ],
  [
    "carrots-1kg",
    "Carrots 1kg",
    22.99,
    "bag",
    "Fresh carrots for snacks, salads, soups and stews.",
  ],
  [
    "toilet-paper-9",
    "Toilet Paper 9 Pack",
    74.99,
    "pack",
    "Nine soft two-ply toilet rolls for household use.",
  ],
  [
    "bath-soap-175g",
    "Bath Soap 175g",
    14.99,
    "bar",
    "Gentle cleansing bath soap for everyday use.",
  ],
  [
    "laundry-powder-2kg",
    "Laundry Powder 2kg",
    84.99,
    "bag",
    "Concentrated washing powder for hand or machine laundry.",
  ],
  [
    "dishwashing-750ml",
    "Dishwashing Liquid 750ml",
    32.99,
    "bottle",
    "Grease-cutting liquid for dishes and kitchen cleaning.",
  ],
  [
    "bleach-750ml",
    "Household Bleach 750ml",
    19.99,
    "bottle",
    "Multipurpose bleach for whitening and household hygiene.",
  ],
  [
    "sanitary-pads-10",
    "Sanitary Pads 10 Pack",
    29.99,
    "pack",
    "Comfortable sanitary pads with secure wings.",
  ],
  [
    "nappies-size-3",
    "Baby Nappies Size 3",
    109.99,
    "pack",
    "Absorbent disposable nappies for babies in size 3.",
  ],
  [
    "toothpaste-100ml",
    "Toothpaste 100ml",
    24.99,
    "tube",
    "Everyday fluoride toothpaste for fresh breath and cavity care.",
  ],
  [
    "roll-on-50ml",
    "Roll-On Deodorant 50ml",
    27.99,
    "bottle",
    "Long-lasting roll-on deodorant for daily freshness.",
  ],
  [
    "matches-10",
    "Matches 10 Pack",
    19.99,
    "pack",
    "Ten boxes of household safety matches.",
  ],
  [
    "candles-6",
    "Household Candles 6 Pack",
    34.99,
    "pack",
    "Six long-burning white candles for home use.",
  ],
  [
    "airtime-r20",
    "Airtime Voucher R20",
    20,
    "voucher",
    "A R20 prepaid airtime voucher delivered as a redeemable code.",
  ],
  [
    "water-6x500ml",
    "Bottled Water 6 x 500ml",
    34.99,
    "pack",
    "Six convenient bottles of still drinking water.",
  ],
  [
    "cola-2l",
    "Cola Soft Drink 2L",
    24.99,
    "bottle",
    "Two-litre bottle of sparkling cola soft drink.",
  ],
  [
    "orange-drink-2l",
    "Orange Drink 2L",
    22.99,
    "bottle",
    "Refreshing orange-flavoured drink in a family-size bottle.",
  ],
  [
    "potato-chips-125g",
    "Potato Chips 125g",
    19.99,
    "packet",
    "Crunchy salted potato chips for sharing or snacking.",
  ],
];

function parseOptions(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) continue;
    const [key, inline] = value.slice(2).split("=", 2);
    const next = argv[index + 1];
    if (inline != null) args.set(key, inline);
    else if (next && !next.startsWith("--")) {
      args.set(key, next);
      index += 1;
    } else args.set(key, true);
  }
  const projectId = String(args.get("project") ?? "").trim();
  const runId = String(args.get("run-id") ?? "").trim();
  const execute = args.get("execute") === true;
  const verify = args.get("verify") === true;
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error(
      "Bot catalogue seed requires an explicit development project.",
    );
  }
  if (execute && verify) throw new Error("Choose --execute or --verify.");
  if ((execute || verify) && !/^[A-Za-z0-9:_-]{1,120}$/.test(runId)) {
    throw new Error("Execute and verify require an explicit run ID.");
  }
  return { projectId, runId, execute, verify };
}

export function validateDevelopmentBotCatalogOptions(argv) {
  return parseOptions(argv);
}

function productImageUrl(name) {
  return `https://placehold.co/800x600/0B4F4A/FFFFFF.png?text=${encodeURIComponent(name)}`;
}

async function run(options) {
  if (!options.execute && !options.verify) {
    console.log(
      JSON.stringify({
        mode: "dry-run",
        projectId: options.projectId,
        merchantId: MERCHANT_ID,
        orderingCode: ORDERING_CODE,
        productCount: PRODUCTS.length,
        synthetic: true,
      }),
    );
    return;
  }

  const db = getFirestore(
    initializeApp({
      projectId: options.projectId,
      credential: applicationDefault(),
    }),
  );
  const merchantRef = db.doc(`users/${MERCHANT_ID}`);
  const referralRef = db.doc(`merchant_referrals/${ORDERING_CODE}`);
  const runRef = db.doc(`developmentBotCatalogRuns/${options.runId}`);

  if (options.verify) {
    const [merchant, referral, runSnap, ...products] = await db.getAll(
      merchantRef,
      referralRef,
      runRef,
      ...PRODUCTS.map(([id]) => merchantRef.collection("products").doc(id)),
    );
    const invalidProducts = products.filter((snapshot) => {
      const data = snapshot.data() ?? {};
      return (
        !snapshot.exists ||
        data.synthetic !== true ||
        data.whatsappListed !== true ||
        !data.description ||
        !data.imageUrl
      );
    });
    const valid =
      merchant.exists &&
      merchant.get("whatsappEligibleOverride") === true &&
      referral.exists &&
      referral.get("merchantId") === MERCHANT_ID &&
      referral.get("status") === "active" &&
      runSnap.exists &&
      runSnap.get("seedVersion") === SEED_VERSION &&
      invalidProducts.length === 0;
    if (!valid) {
      throw new Error(
        `DEVELOPMENT_BOT_CATALOG_VERIFICATION_FAILED invalidProducts=${invalidProducts.length}`,
      );
    }
    console.log(
      JSON.stringify({
        mode: "verify",
        projectId: options.projectId,
        runId: options.runId,
        verified: true,
        productCount: products.length,
        orderingCode: ORDERING_CODE,
      }),
    );
    return;
  }

  let deduped = false;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(runRef);
    if (existing.exists) {
      if (existing.get("seedVersion") !== SEED_VERSION) {
        throw new Error("DEVELOPMENT_BOT_CATALOG_RUN_BINDING_MISMATCH");
      }
      deduped = true;
      return;
    }
    const now = FieldValue.serverTimestamp();
    tx.set(
      merchantRef,
      {
        name: "SpazaOne Dev Merchant",
        shopName: "SpazaOne Development Store",
        hasProducts: true,
        whatsappEligibleOverride: true,
        appVersion: "4.8.0",
        synthetic: true,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.set(
      referralRef,
      {
        merchantId: MERCHANT_ID,
        status: "active",
        type: "whatsapp_ordering",
        useCount: 0,
        synthetic: true,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
    PRODUCTS.forEach(
      ([id, name, sellingPrice, unit, description, aliases], index) => {
        tx.set(
          merchantRef.collection("products").doc(id),
          {
            name,
            description,
            sellingPrice,
            cost: Math.round(Number(sellingPrice) * 70) / 100,
            unit,
            aliases: aliases ?? [],
            imageUrl: productImageUrl(name),
            whatsappListed: true,
            whatsappPopularityScore: index < 5 ? 100 - index : 0,
            quantity: 100,
            isDropshipListing: false,
            synthetic: true,
            developmentBotCatalogRunId: options.runId,
            updatedAt: now,
          },
          { merge: true },
        );
      },
    );
    tx.create(runRef, {
      runId: options.runId,
      projectId: options.projectId,
      merchantId: MERCHANT_ID,
      orderingCode: ORDERING_CODE,
      productCount: PRODUCTS.length,
      seedVersion: SEED_VERSION,
      synthetic: true,
      status: "applied",
      createdAt: now,
    });
  });
  console.log(
    JSON.stringify({
      mode: "execute",
      projectId: options.projectId,
      runId: options.runId,
      productCount: PRODUCTS.length,
      orderingCode: ORDERING_CODE,
      synthetic: true,
      deduped,
    }),
  );
}

async function main() {
  await run(parseOptions(process.argv.slice(2)));
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  await main();
}
