# Payment Provider Wallet & Order Features

## Wallet

- **Cash Withdrawal vs. Banking Details**
  - Notify users via email or other methods when a withdrawal is requested.
- **In-App Spending**
- **Activate Paystack for production**

## Orders & Payments

- **Platform fee for all online transactions**
- **Transaction fee for online sales**
- **Supported payment methods**
  - Cash orders (no platform fee)
  - Online payments via Paystack
  - Wallet balance for in-app purchases

## Paystack Fees (South Africa)

### 1. Local Payments (cards, Scan to Pay, SnapScan)

- 2.9% + R1.00 per transaction (excl. VAT)
- Add 15% VAT on the fee.
- Effective: ~3.3%–3.4% all-in once VAT is factored.

### 2. Bank EFT (Ozow / Instant EFT)

- 2% flat (excl. VAT)
- With VAT: 2.3% effective.
- No R1.00 flat fee here.

### 3. International Payments

- 3.1% + R1.00 (excl. VAT)
- With VAT: ~3.55%–3.6% effective.
- Supports Visa, Mastercard, Amex, etc.

### 4. Settlement payouts and outbound transfers

- Automatic Paystack settlement payouts are free.
- A separate outbound transfer initiated through Paystack's Transfers API is
  R3.00 (excl. VAT → R3.45 incl. VAT), whether successful or failed.

## Worked Examples

### Example 1: Local Card Transaction — R1 000 sale

- Base fee: 2.9% of 1,000 = R29
- Flat: R1 → R30
- VAT: 15% of R30 = R4.50
- Total fee = R34.50
- Merchant receives = R965.50

### Example 2: EFT Transaction — R1 000 sale

- Base fee: 2% of 1,000 = R20
- VAT: R3.00
- Total fee = R23.00
- Merchant receives = R977.00

### Example 3: International Card — R1 000 sale

- Base fee: 3.1% of 1,000 = R31
- Flat: R1 → R32
- VAT: R4.80
- Total fee = R36.80
- Merchant receives = R963.20

## Key Takeaways

- EFT is cheapest (2.3% effective).
- Local cards average ~3.3–3.4%.
- International cards cost the most (~3.6%).
- Do not add a fee for normal automatic settlement payouts.
- Add R3.45 only when SpazaOne explicitly initiates an outbound bank transfer
  through Paystack's Transfers API.
