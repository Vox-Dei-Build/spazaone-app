#!/usr/bin/env bash
# Verify an iOS .ipa for invalid PrivacyInfo.xcprivacy files BEFORE
# uploading to App Store Connect. Apple's ITMS-91056 rejection takes
# ~45 minutes to come back via email; this catches the same class of
# errors locally in seconds.
#
# Usage:
#   scripts/verify_ios_privacy.sh path/to/Pasella.ipa
#   scripts/verify_ios_privacy.sh build/ios/ipa/pasella.ipa
#
# Exits 0 if all manifests are valid (or absent for known-bad plugins),
# non-zero otherwise. Mirrors the assertion logic that runs in
# codemagic.yaml's "Verify IPA privacy manifests are valid" step.

set -euo pipefail

IPA="${1:-}"
if [ -z "$IPA" ]; then
  # Default to the most recent IPA produced by `flutter build ipa`.
  IPA=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -n1 || true)
fi
if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
  echo "Usage: $0 <path-to-ipa>" >&2
  echo "       (no IPA argument given and none found under build/ios/ipa/)" >&2
  exit 2
fi

echo "Verifying privacy manifests in: $IPA"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"
APP_DIR=$(ls -d "$WORK"/Payload/*.app | head -n1)

# 1. flutter_app_badger_plus_privacy.bundle must NOT be present.
STRAY=$(find "$APP_DIR" -iname "*flutter_app_badger_plus*privacy*" 2>/dev/null || true)
if [ -n "$STRAY" ]; then
  echo "::error:: flutter_app_badger_plus privacy bundle still in IPA (Apple will reject):"
  echo "$STRAY"
  exit 1
fi

# 2. Every remaining PrivacyInfo.xcprivacy must be schema-valid.
ALL_MANIFESTS=$(find "$APP_DIR" -name "PrivacyInfo.xcprivacy" 2>/dev/null || true)
if [ -z "$ALL_MANIFESTS" ]; then
  echo "No PrivacyInfo.xcprivacy files in IPA. ✓"
  exit 0
fi

echo "Found $(echo "$ALL_MANIFESTS" | wc -l | tr -d ' ') privacy manifest(s):"
INVALID=0
while IFS= read -r M; do
  [ -z "$M" ] && continue
  if ! plutil -lint "$M" >/dev/null 2>&1; then
    echo "::error:: $M is not valid plist XML"
    INVALID=1
    continue
  fi
  python3 - "$M" <<'PY' || INVALID=1
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    data = plistlib.load(f)
bad = []
for key in ('NSPrivacyAccessedAPITypes', 'NSPrivacyCollectedDataTypes'):
    for i, entry in enumerate(data.get(key, [])):
        if not isinstance(entry, dict) or len(entry) == 0:
            bad.append(f"{key}[{i}] is empty/invalid")
            continue
        required = 'NSPrivacyAccessedAPIType' if key == 'NSPrivacyAccessedAPITypes' else 'NSPrivacyCollectedDataType'
        if required not in entry:
            bad.append(f"{key}[{i}] missing required key {required}")
if bad:
    print(f"::error:: Invalid manifest {path}:")
    for b in bad:
        print(f"  - {b}")
    sys.exit(1)
print(f"  ✓ {path}")
PY
done <<< "$ALL_MANIFESTS"

if [ "$INVALID" != "0" ]; then
  echo
  echo "::error:: One or more privacy manifests would be rejected by Apple (ITMS-91056)."
  exit 1
fi
echo
echo "All privacy manifests valid ✓"
