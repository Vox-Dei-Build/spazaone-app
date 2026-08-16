import { failureOutcome, FailureOutcome } from "./domain";

export const FAILURE_SCENARIO_IDS = [
  "invalid_webhook_signature",
  "replayed_webhook",
  "duplicate_provider_event",
  "out_of_order_provider_event",
  "delayed_callback",
  "app_closed_after_payment",
  "abandoned_checkout",
  "amount_mismatch",
  "currency_mismatch",
  "merchant_mismatch",
  "order_mismatch",
  "cancelled_order_payment",
  "already_paid_order",
  "initialize_timeout",
  "refund_timeout",
  "partial_refund",
  "full_refund",
  "settlement_mismatch",
  "bank_destination_changed",
  "inventory_unavailable",
  "cj_stock_changed",
  "cj_price_changed",
  "cj_balance_insufficient",
  "cj_created_payment_failed",
  "notification_failed_after_payment",
  "botpress_failed_after_payment",
  "kill_switch_before_initialization",
  "kill_switch_after_initialization",
  "kill_switch_after_payment",
] as const;

export type FailureScenarioId = (typeof FAILURE_SCENARIO_IDS)[number];

export type FailureRehearsal = {
  id: FailureScenarioId;
  charged: boolean;
  retryable: boolean;
  fulfilled: boolean;
  refundPending: boolean;
  expectedOutcome: FailureOutcome;
  control: string;
};

/**
 * Executable I2 pre-mortem. A new failure mode is incomplete until it is
 * assigned an accountable terminal outcome and a concrete control.
 */
export const FAILURE_REHEARSALS: readonly FailureRehearsal[] = [
  {
    id: "invalid_webhook_signature",
    charged: false,
    retryable: false,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "no_charge",
    control: "Reject before event persistence or business mutation.",
  },
  {
    id: "replayed_webhook",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Provider-event identity and intent event set deduplicate replay.",
  },
  {
    id: "duplicate_provider_event",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Transactionally apply the provider event exactly once.",
  },
  {
    id: "out_of_order_provider_event",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Fail-closed state transitions never regress a paid intent.",
  },
  {
    id: "delayed_callback",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Signed provider event, not browser callback, advances payment.",
  },
  {
    id: "app_closed_after_payment",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Server event processing is independent from application state.",
  },
  {
    id: "abandoned_checkout",
    charged: false,
    retryable: false,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "no_charge",
    control: "Expire the intent and release reservations exactly once.",
  },
  ...[
    "amount_mismatch",
    "currency_mismatch",
    "merchant_mismatch",
    "order_mismatch",
    "cancelled_order_payment",
  ].map((id) => ({
    id: id as FailureScenarioId,
    charged: true,
    retryable: false,
    fulfilled: false,
    refundPending: true,
    expectedOutcome: "paid_refund_pending" as FailureOutcome,
    control: "Quarantine the mismatch and open a provider-backed refund case.",
  })),
  {
    id: "already_paid_order",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Same reference deduplicates; a different charge opens refund.",
  },
  {
    id: "initialize_timeout",
    charged: false,
    retryable: true,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "safely_retryable",
    control: "Recover by idempotency key and verify before reinitializing.",
  },
  {
    id: "refund_timeout",
    charged: true,
    retryable: true,
    fulfilled: false,
    refundPending: true,
    expectedOutcome: "paid_refund_pending",
    control: "Keep refund pending and retry by immutable refund-case key.",
  },
  ...["partial_refund", "full_refund"].map((id) => ({
    id: id as FailureScenarioId,
    charged: true,
    retryable: false,
    fulfilled: false,
    refundPending: true,
    expectedOutcome: "paid_refund_pending" as FailureOutcome,
    control: "Remain pending until Paystack confirms the exact refund amount.",
  })),
  {
    id: "settlement_mismatch",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "Freeze activation and surface the mismatch in reconciliation.",
  },
  {
    id: "bank_destination_changed",
    charged: false,
    retryable: true,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "safely_retryable",
    control: "Suspend merchant collection until the destination is reverified.",
  },
  {
    id: "inventory_unavailable",
    charged: false,
    retryable: false,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "no_charge",
    control: "Atomic reservation must succeed before initialization.",
  },
  ...["cj_stock_changed", "cj_price_changed", "cj_balance_insufficient"].map(
    (id) => ({
      id: id as FailureScenarioId,
      charged: true,
      retryable: true,
      fulfilled: false,
      refundPending: true,
      expectedOutcome: "paid_refund_pending" as FailureOutcome,
      control:
        "Revalidate before checkout and again after charge; if supplier truth changed in between, request a full provider refund.",
    }),
  ),
  {
    id: "cj_created_payment_failed",
    charged: true,
    retryable: true,
    fulfilled: false,
    refundPending: true,
    expectedOutcome: "paid_refund_pending",
    control:
      "Reconcile CJ idempotently; cancel there or refund through Paystack.",
  },
  ...["notification_failed_after_payment", "botpress_failed_after_payment"].map(
    (id) => ({
      id: id as FailureScenarioId,
      charged: true,
      retryable: true,
      fulfilled: true,
      refundPending: false,
      expectedOutcome: "paid_and_fulfilled" as FailureOutcome,
      control: "Money state commits first; an outbox retries communication.",
    }),
  ),
  {
    id: "kill_switch_before_initialization",
    charged: false,
    retryable: false,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "no_charge",
    control: "Deny initialization before an external request is made.",
  },
  {
    id: "kill_switch_after_initialization",
    charged: false,
    retryable: true,
    fulfilled: false,
    refundPending: false,
    expectedOutcome: "safely_retryable",
    control: "Stop new attempts while still accepting signed terminal events.",
  },
  {
    id: "kill_switch_after_payment",
    charged: true,
    retryable: false,
    fulfilled: true,
    refundPending: false,
    expectedOutcome: "paid_and_fulfilled",
    control: "A kill switch never abandons already captured money.",
  },
] as const;

export function validateFailureRehearsals(
  rehearsals: readonly FailureRehearsal[] = FAILURE_REHEARSALS,
): void {
  const seen = new Set<string>();
  for (const scenario of rehearsals) {
    if (seen.has(scenario.id))
      throw new Error(`SCENARIO_DUPLICATE:${scenario.id}`);
    seen.add(scenario.id);
    if (!scenario.control.trim())
      throw new Error(`CONTROL_MISSING:${scenario.id}`);
    const actual = failureOutcome(scenario);
    if (actual !== scenario.expectedOutcome) {
      throw new Error(`OUTCOME_MISMATCH:${scenario.id}:${actual}`);
    }
  }
  for (const id of FAILURE_SCENARIO_IDS) {
    if (!seen.has(id)) throw new Error(`SCENARIO_MISSING:${id}`);
  }
}
