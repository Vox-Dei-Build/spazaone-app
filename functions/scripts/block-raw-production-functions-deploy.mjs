#!/usr/bin/env node

process.stderr.write(
  `${JSON.stringify({
    outcome: "blocked",
    code: "RAW_PRODUCTION_FUNCTIONS_DEPLOY_DISABLED",
    retryAllowed: false,
    requiredRoute: "catalog:deploy:guard",
  })}\n`,
);
process.exitCode = 1;
