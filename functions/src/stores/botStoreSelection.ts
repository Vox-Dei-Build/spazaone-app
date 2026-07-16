export type BotStoreChoice = {
  merchantId: string;
  shopName: string;
  role: string;
};

export type BotStoreResolution =
  | { kind: "selected"; store: BotStoreChoice }
  | { kind: "none" }
  | { kind: "forbidden" }
  | { kind: "selection-required"; stores: BotStoreChoice[] };

/** Deterministic store selection shared by the bot endpoint and tests. */
export function resolveBotStore(
  rawStores: BotStoreChoice[],
  requestedStoreId: string,
  requestedChoice: string,
): BotStoreResolution {
  const stores = [...rawStores]
    .filter(
      (store, index, all) =>
        Boolean(store.merchantId) &&
        all.findIndex(
          (candidate) => candidate.merchantId === store.merchantId,
        ) === index,
    )
    .sort(
      (left, right) =>
        left.shopName.localeCompare(right.shopName) ||
        left.merchantId.localeCompare(right.merchantId),
    );
  const requested = requestedStoreId.trim();
  if (requested) {
    const selected = stores.find((store) => store.merchantId === requested);
    return selected
      ? { kind: "selected", store: selected }
      : { kind: "forbidden" };
  }

  const choice = Number(requestedChoice);
  if (Number.isInteger(choice) && choice >= 1 && choice <= stores.length) {
    return { kind: "selected", store: stores[choice - 1] };
  }
  if (stores.length === 0) return { kind: "none" };
  if (stores.length === 1) return { kind: "selected", store: stores[0] };
  return { kind: "selection-required", stores };
}
