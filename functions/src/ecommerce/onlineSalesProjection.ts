type AnyMap = { [key: string]: any };

function nonNegativeMinor(value: unknown, field: string): number {
  const amount = Number(value ?? 0);
  if (!Number.isSafeInteger(amount) || amount < 0) {
    throw new Error(`${field.toUpperCase()}_INVALID`);
  }
  return amount;
}

export function projectPaymentsV2OwnedSale(input: {
  merchantId: string;
  saleId: string;
  sale: AnyMap;
  intent?: AnyMap;
}): AnyMap {
  const { merchantId, saleId, sale } = input;
  if (String(sale.paymentRail ?? "") !== "paystack_v2") {
    throw new Error("PAYMENT_RAIL_INVALID");
  }

  const intentId = String(sale.paymentIntentId ?? "").trim();
  const intent = input.intent ?? {};
  if (intentId) {
    if (
      String(intent.intentId ?? "") !== intentId ||
      String(intent.merchantId ?? "") !== merchantId ||
      String(intent.purpose ?? "") !== "merchant_order" ||
      String(intent.businessBinding?.type ?? "") !== "owned_order" ||
      String(intent.businessBinding?.id ?? "") !== saleId
    ) {
      throw new Error("OWNED_ORDER_PAYMENT_BINDING_MISMATCH");
    }
  }

  const rawOrderTotal = Number(
    sale.total ?? sale.amount ?? sale.saleTotal ?? 0,
  );
  if (!Number.isFinite(rawOrderTotal) || rawOrderTotal < 0) {
    throw new Error("ORDER_TOTAL_INVALID");
  }
  const orderTotalMinor = nonNegativeMinor(
    Math.round(rawOrderTotal * 100),
    "order_total",
  );
  const expectedAmountMinor = nonNegativeMinor(
    intent.expectedAmountMinor ?? orderTotalMinor,
    "expected_amount",
  );
  if (
    intentId &&
    orderTotalMinor > 0 &&
    expectedAmountMinor !== orderTotalMinor
  ) {
    throw new Error("OWNED_ORDER_AMOUNT_MISMATCH");
  }

  const providerAmountMinor = nonNegativeMinor(
    intent.providerAmountMinor ?? 0,
    "provider_amount",
  );
  const intentStatus = String(intent.status ?? "").toLowerCase();
  const charged = ["paid", "refund_pending", "refunded", "disputed"].includes(
    intentStatus,
  );
  if (charged && providerAmountMinor !== expectedAmountMinor) {
    throw new Error("OWNED_ORDER_PROVIDER_AMOUNT_MISMATCH");
  }

  const actualMoney = intent.actualMoney ?? {};
  const platformFeeMinor = charged
    ? nonNegativeMinor(actualMoney.platformFeeMinor, "platform_fee")
    : 0;
  const providerFeeMinor = charged
    ? nonNegativeMinor(actualMoney.providerFeeMinor, "provider_fee")
    : 0;
  const merchantNetMinor = charged
    ? nonNegativeMinor(
        actualMoney.merchantNetProceedsMinor,
        "merchant_net_proceeds",
      )
    : 0;
  if (
    charged &&
    platformFeeMinor + providerFeeMinor + merchantNetMinor !==
      providerAmountMinor
  ) {
    throw new Error("OWNED_ORDER_MONEY_SNAPSHOT_MISMATCH");
  }

  const itemsCount = Number(
    sale.itemsCount ??
      (sale.products && typeof sale.products === "object"
        ? Object.values(sale.products).reduce(
            (total: number, quantity: any) => total + Number(quantity || 0),
            0,
          )
        : 0),
  );
  if (!Number.isSafeInteger(itemsCount) || itemsCount < 0) {
    throw new Error("ITEMS_COUNT_INVALID");
  }

  return {
    id: saleId,
    reference: String(sale.paymentReference ?? intent.providerReference ?? ""),
    status: String(sale.status ?? "pending_payment"),
    paymentMethod: String(sale.paymentMethod ?? "Online"),
    paymentStatus: String(sale.paymentStatus ?? "pending"),
    itemsCount,
    createdAt: sale.dateAdded ?? sale.createdAt ?? null,
    ledgerCreatedAt: intent.paidAt ?? intent.createdAt ?? null,
    orderTotal: orderTotalMinor / 100,
    amountPaid: charged ? providerAmountMinor / 100 : 0,
    feeExVat: 0,
    feeInclVat: charged ? (platformFeeMinor + providerFeeMinor) / 100 : 0,
    netAmount: charged ? merchantNetMinor / 100 : 0,
    currency: String(sale.currency ?? "ZAR"),
    method: String(sale.channelUsed ?? intent.selectedChannel ?? ""),
    channel: String(sale.channelUsed ?? intent.selectedChannel ?? ""),
  };
}
