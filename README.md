# Pasella Ledger

### Project Structure

#### The project structure is organized in the following way:

- constants: contains the constants (mainly for themeing)
- lib: contains the main Dart code for the application
- pages: contains the different screens for the application
- widgets: contains the various common widgets used throughout the application
- assets: contains any necessary assets used in the application

### Installation

#### Clone the repository using the following command:

#### Rename the project directory before running flutter commands

```bash
mv pasella-app pasella
```

#### Navigate to the project directory:

```bash
cd pasella
```

#### Install the dependencies:

```bash
flutter pub get
```

#### Run the application:

```bash
flutter run
```

### Remote Config Keys

The application relies on Firebase Remote Config for messaging templates and
dynamic pricing. Ensure the following keys are configured:

#### Twilio Template IDs

- `TWILIO_ACCEPT_BNPL_TID`
- `TWILIO_REJECT_BNPL_TID`
- `TWILIO_MARK_CASH_RECEIVED_TID`
- `TWILIO_MARK_COLLECTED_TID`
- `TWILIO_SETTLE_BNPL_TID`
- `TWILIO_CANCEL_ORDER_TID`

#### Pricing Parameters

- `USD_SMS_REMINDER_PRICE`
- `USD_SMS_PAYMENT_PRICE`
- `USD_WHATSAPP_UTILITY_PRICE`
- `USD_WHATSAPP_PROMOTIONAL_PRICE`
- `MARKUP_SMS_PERCENTAGE`
- `MARKUP_WHATSAPP_PERCENTAGE`
- `MARKUP_PROMOTIONAL_PERCENTAGE`
- `USD_ZAR_EXCHANGE_RATE`
- `PAYSTACK_LOCAL_PERCENT`
- `PAYSTACK_LOCAL_FLAT`
- `PAYSTACK_EFT_PERCENT`
- `PAYSTACK_INT_PERCENT`
- `PAYSTACK_INT_FLAT`
- `PAYSTACK_SETTLEMENT_FEE`
- `PAYSTACK_VAT_PERCENT`

### Payment Provider, Orders & Wallet

Additional notes on the in-app wallet, order payment options, and payment provider markup are documented in
[`docs/payment_provider_wallet.md`](docs/payment_provider_wallet.md).

### Releases

Pasella ships from `main` directly, tag-driven, no release branches.
See [`docs/releases.md`](docs/releases.md) for the full ritual,
trigger semantics, required env vars, and recovery playbook.

Quick reference:

```bash
# bump pubspec.yaml version, commit, then:
git tag -a v3.0.3+48 -m "Release 3.0.3+48"
git push origin v3.0.3+48     # fires both Android + iOS workflows
```

Plain pushes to `main` do NOT trigger a build — only tags matching
`v*.*.*+*` do.
