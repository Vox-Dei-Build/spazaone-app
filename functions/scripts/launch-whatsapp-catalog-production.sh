#!/bin/sh

set -eu

PATH=/usr/bin:/bin
export PATH

LAUNCHER_PATH=$(
  CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" && /bin/pwd -P
)/launch-whatsapp-catalog-production.sh
EXECUTOR_PATH=$(
  CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" && /bin/pwd -P
)/execute-whatsapp-catalog-production.mjs

if [ ! -c /dev/tty ]; then
  /usr/bin/printf '%s\n' '{"outcome":"blocked","code":"PRODUCTION_ACTION_CONTROLLING_TTY_REQUIRED","retryAllowed":false}' >&2
  exit 1
fi

# Hold the exact launcher inode open for the complete Node process. The
# executor verifies this descriptor, strips ambient credential variables, and
# obtains action-time authority only from the controlling TTY.
exec 3<"$LAUNCHER_PATH"
exec /usr/bin/env -i \
  HOME=/Users/admin \
  USER=admin \
  LOGNAME=admin \
  TMPDIR=/private/tmp \
  LANG=C \
  LC_ALL=C \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  SPAZAONE_PRODUCTION_EXECUTOR_LAUNCHER_PATH="$LAUNCHER_PATH" \
  SPAZAONE_PRODUCTION_EXECUTOR_LAUNCHER_FD=3 \
  /opt/homebrew/bin/node "$EXECUTOR_PATH" "$@" 3<&3
