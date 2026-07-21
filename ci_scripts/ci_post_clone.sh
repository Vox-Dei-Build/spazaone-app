#!/bin/sh

# Xcode Cloud checks out source without Flutter-generated iOS files or Pods.
# Bootstrap the exact Flutter toolchain used to validate this release before
# Xcode starts the archive action.

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

REPOSITORY_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
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
flutter config --no-analytics
flutter precache --ios
flutter pub get

# This release already uses the same App Store privacy-manifest workaround in
# Codemagic. Apply it before CocoaPods resolves the plugin in Xcode Cloud too.
./scripts/strip_badger_privacy.sh

cd ios
pod install --repo-update
