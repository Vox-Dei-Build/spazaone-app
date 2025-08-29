import * as crypto from "crypto";

/**
 * Computes a deterministic SHA-256 signature for a shopping cart.
 *
 * Normalizes the cart items by:
 * - Casting `productId` to a string.
 * - Converting `quantity` and `unit` to numbers (defaulting to 0 if missing).
 * - Filtering out items with zero or negative quantity.
 * - Sorting items by `productId` to ensure consistent order.
 *
 * The normalized cart is then serialized to JSON and hashed using SHA-256.
 * This ensures that carts with the same contents always produce the same signature,
 * regardless of item ordering or input formatting.
 *
 * @function computeCartSig
 * @param {Array<{ productId: string, quantity: number, unit: number }>} items -
 *   The raw cart items, each containing product ID, quantity, and unit price/amount.
 * @return {string} A hex-encoded SHA-256 hash representing the normalized cart contents.
 *
 * @example
 * const sig = computeCartSig([
 *   { productId: "A1", quantity: 2, unit: 50 },
 *   { productId: "B2", quantity: 1, unit: 100 },
 * ]);
 * console.log(sig); // "e3f7b6..."
 */
export function computeCartSig(
  items: Array<{ productId: string; quantity: number; unit: number }>,
) {
  const norm = items
    .map((x) => ({
      id: String(x.productId),
      q: Number(x.quantity || 0),
      u: Number(x.unit || 0),
    }))
    .filter((x) => x.q > 0)
    .sort((a, b) => a.id.localeCompare(b.id));
  const json = JSON.stringify(norm);
  return crypto.createHash("sha256").update(json).digest("hex");
}
