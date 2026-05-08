#!/usr/bin/env bash
# Strip the broken flutter_app_badger_plus PrivacyInfo.xcprivacy that
# triggers App Store Connect ITMS-91056 rejection.
#
# WHY: flutter_app_badger_plus 1.0.1 (Dart) / 1.3.0 (podspec) ships
# an invalid PrivacyInfo.xcprivacy with empty <dict/> entries in
# NSPrivacyAccessedAPITypes and NSPrivacyCollectedDataTypes. Apple
# rejects the IPA with ITMS-91056 ~45 minutes after upload.
#
# The plugin only sets a UIApplication notification badge; not in
# Apple's required-reasons list, so no manifest is required at all.
#
# WHAT: this script removes the privacy file from BOTH locations and
# patches the podspec to remove the s.resource_bundles declaration so
# CocoaPods never creates the flutter_app_badger_plus_privacy.bundle
# in the first place. Without the resource bundle declaration the
# manifest cannot resurface in any IPA.
#
# Idempotent. Fails loudly if expected files don't exist (silent
# fallback is what let two builds ship broken to Apple).
#
# Run from the repo root, BEFORE `pod install` and BEFORE
# `flutter build ipa`. Wired into codemagic.yaml ios-release as
# its own step.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Stripping flutter_app_badger_plus privacy manifest in $REPO_ROOT"

DELETED_COUNT=0
PATCHED_COUNT=0

# 1. Delete every flutter_app_badger_plus PrivacyInfo.xcprivacy.
#    Locations: pub-cache (source of truth that pub get rehydrates
#    into the symlink) and ios/.symlinks/plugins/ (the symlink itself,
#    which on some platforms is a real copy not a symlink).
SEARCH_ROOTS=(
  "$HOME/.pub-cache/hosted/pub.dev"
  "$REPO_ROOT/ios/.symlinks/plugins"
)
for ROOT in "${SEARCH_ROOTS[@]}"; do
  [ -d "$ROOT" ] || continue
  while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    rm -f "$FILE"
    echo "  deleted: $FILE"
    DELETED_COUNT=$((DELETED_COUNT + 1))
  done < <(find "$ROOT" -path "*flutter_app_badger_plus*" -name PrivacyInfo.xcprivacy 2>/dev/null)
done

# 2. Patch every flutter_app_badger_plus podspec to remove the
#    s.resource_bundles line. Without this line, CocoaPods will not
#    declare a flutter_app_badger_plus_privacy bundle target and the
#    manifest cannot make it into the IPA even if a future
#    `flutter pub get` rehydrates the source file.
for ROOT in "${SEARCH_ROOTS[@]}"; do
  [ -d "$ROOT" ] || continue
  while IFS= read -r SPEC; do
    [ -z "$SPEC" ] && continue
    if grep -q "resource_bundles" "$SPEC"; then
      # macOS sed needs '' after -i; -E for extended regex; remove the
      # whole resource_bundles line(s).
      sed -i.bak -E '/s\.resource_bundles[[:space:]]*=/d' "$SPEC"
      rm -f "$SPEC.bak"
      echo "  patched podspec (removed resource_bundles): $SPEC"
      PATCHED_COUNT=$((PATCHED_COUNT + 1))
    fi
  done < <(find "$ROOT" -path "*flutter_app_badger_plus*" -name "*.podspec" 2>/dev/null)
done

# 3. Verify end state: at least one flutter_app_badger_plus podspec
#    must exist AND none of them may declare resource_bundles AND no
#    PrivacyInfo.xcprivacy may remain in any flutter_app_badger_plus
#    directory. Idempotent: re-running on already-stripped state is
#    success. Fails loudly only if the plugin can't be found at all
#    or if any unpatched podspec / unstripped manifest remains.
PODSPEC_COUNT=0
BAD_PODSPEC=0
BAD_MANIFEST=0
for ROOT in "${SEARCH_ROOTS[@]}"; do
  [ -d "$ROOT" ] || continue
  while IFS= read -r SPEC; do
    [ -z "$SPEC" ] && continue
    PODSPEC_COUNT=$((PODSPEC_COUNT + 1))
    if grep -q "resource_bundles" "$SPEC"; then
      echo "::error:: podspec still declares resource_bundles: $SPEC" >&2
      BAD_PODSPEC=$((BAD_PODSPEC + 1))
    fi
  done < <(find "$ROOT" -path "*flutter_app_badger_plus*" -name "*.podspec" 2>/dev/null)
  while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    echo "::error:: manifest still present: $FILE" >&2
    BAD_MANIFEST=$((BAD_MANIFEST + 1))
  done < <(find "$ROOT" -path "*flutter_app_badger_plus*" -name PrivacyInfo.xcprivacy 2>/dev/null)
done

if [ "$PODSPEC_COUNT" -eq 0 ]; then
  echo "::error:: Found no flutter_app_badger_plus podspec in:" >&2
  for ROOT in "${SEARCH_ROOTS[@]}"; do
    echo "  - $ROOT" >&2
  done
  echo "Plugin may have been removed upstream or pub get hasn't run yet. Run 'flutter pub get' first, or remove this strip step if the dependency was dropped." >&2
  exit 1
fi

if [ "$BAD_PODSPEC" -gt 0 ] || [ "$BAD_MANIFEST" -gt 0 ]; then
  echo "::error:: Strip incomplete: $BAD_PODSPEC unpatched podspec(s), $BAD_MANIFEST remaining manifest(s)." >&2
  exit 1
fi

echo "Strip OK: $DELETED_COUNT manifest(s) deleted this run, $PATCHED_COUNT podspec(s) patched this run, $PODSPEC_COUNT podspec(s) verified clean."
