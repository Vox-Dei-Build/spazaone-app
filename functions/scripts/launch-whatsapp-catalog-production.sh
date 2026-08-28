#!/bin/sh

set -eu

# A reviewed launcher-to-executor session capability has not been authorized.
# Stop in the shell before any Node process or path-loaded writer can run.
/usr/bin/printf '%s\n' '{"outcome":"blocked","code":"PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED","retryAllowed":false}' >&2
exit 1
