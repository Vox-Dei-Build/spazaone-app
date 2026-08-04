/**
 * Digital payment is deliberately fail-closed until provider approval is
 * complete. Manual order requests remain available while this is false.
 */
export function commercePaymentsEnabled(): boolean {
  return (
    String(process.env.COMMERCE_PAYMENTS_ENABLED ?? "")
      .trim()
      .toLowerCase() === "true"
  );
}
