#!/usr/bin/env bash
set -euo pipefail

export QA_FIREBASE_PROJECT_ID=demo-spazaone-qa
export QA_DEVICE_FIREBASE_HOST=127.0.0.1
export SPAZAONE_ENVIRONMENT=local
export PAYSTACK_PROVIDER_MODE=test
export PAYMENTS_V2_MASTER_ENABLED=false
export COMMERCE_PAYMENTS_ENABLED=false
export CJ_SANDBOX_MODE=true

npm --prefix functions run seed:qa
node functions/scripts/rehearse-payments-v2-migration.mjs \
  --project demo-spazaone-qa \
  --run-id payments-v2-local-rehearsal
node functions/scripts/rehearse-payments-v2-migration.mjs \
  --project demo-spazaone-qa \
  --run-id payments-v2-local-rehearsal \
  --execute
node functions/scripts/rehearse-payments-v2-migration.mjs \
  --project demo-spazaone-qa \
  --run-id payments-v2-local-rehearsal \
  --verify
node functions/scripts/rehearse-payments-v2-migration.mjs \
  --project demo-spazaone-qa \
  --run-id payments-v2-local-rehearsal \
  --execute
npm --prefix functions run test:payments-v2-integration
npm --prefix functions run test:rules
