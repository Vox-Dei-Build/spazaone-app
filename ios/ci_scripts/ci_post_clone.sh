#!/bin/sh

# Xcode Cloud checks out source without Flutter-generated iOS files or Pods.
# Bootstrap the exact Flutter toolchain used to validate this release before
# Xcode starts the archive action.

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

REPOSITORY_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
FLUTTER_ROOT="$HOME/flutter-3.29.2"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  git clone \
    --branch 3.29.2 \
    --depth 1 \
    https://github.com/flutter/flutter.git \
    "$FLUTTER_ROOT"
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"

cd "$REPOSITORY_ROOT"

# `.env` is intentionally gitignored, but Flutter declares it as an asset.
# Build the iOS-only Firebase entries from the committed plist so Xcode Cloud
# can archive without committing local or server-side secrets.
FIREBASE_PLIST="$REPOSITORY_ROOT/ios/GoogleService-Info.plist"
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$FIREBASE_PLIST"
}
{
  printf 'FIREBASE_IOS_API_KEY=%s\n' "$(plist_value API_KEY)"
  printf 'FIREBASE_IOS_APP_ID=%s\n' "$(plist_value GOOGLE_APP_ID)"
  printf 'FIREBASE_IOS_MESSAGING_SENDER_ID=%s\n' "$(plist_value GCM_SENDER_ID)"
  printf 'FIREBASE_IOS_PROJECT_ID=%s\n' "$(plist_value PROJECT_ID)"
  printf 'FIREBASE_IOS_STORAGE_BUCKET=%s\n' "$(plist_value STORAGE_BUCKET)"
  printf 'FIREBASE_IOS_CLIENT_ID=%s\n' \
    "$(/usr/libexec/PlistBuddy -c 'Print :CLIENT_ID' "$FIREBASE_PLIST" 2>/dev/null || true)"
  printf 'FIREBASE_IOS_BUNDLE_ID=%s\n' "$(plist_value BUNDLE_ID)"
} > .env

flutter config --no-analytics
flutter precache --ios
flutter pub get

# Xcode Cloud is a backup CI path, not a release authority. Keep any archive it
# produces behaviorally aligned with the canonical Codemagic build instead of
# silently compiling the stable V1 catalogue aliases.
flutter build ios --config-only --release \
  --dart-define=DROPSHIP_CATALOG_V2=true \
  --dart-define=USE_FIREBASE_EMULATORS=false

# This release already uses the same App Store privacy-manifest workaround in
# Codemagic. Apply it before CocoaPods resolves the plugin in Xcode Cloud too.
./scripts/strip_badger_privacy.sh

cd ios
pod install --repo-update
