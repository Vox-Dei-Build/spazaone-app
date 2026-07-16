#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

swift scripts/generate_app_icon.swift
dart run flutter_launcher_icons

# flutter_launcher_icons 0.13 generates adaptive foregrounds but not the
# Android 13 monochrome layer. Keep the themed icon in sync at every density.
for density_and_size in \
  "mdpi 108" \
  "hdpi 162" \
  "xhdpi 216" \
  "xxhdpi 324" \
  "xxxhdpi 432"; do
  read -r density size <<<"$density_and_size"
  destination="android/app/src/main/res/drawable-${density}/ic_launcher_monochrome.png"
  sips -z "$size" "$size" assets/images/ic_launcher_monochrome.png --out "$destination" >/dev/null
done

# The launcher package rewrites this file and currently omits Android 13's
# monochrome element, so add it back deterministically.
launcher_xml="android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
if ! grep -q '<monochrome ' "$launcher_xml"; then
  LC_ALL=C perl -0pi -e 's!(  <foreground android:drawable="\@drawable/ic_launcher_foreground"/>\n)!$1  <monochrome android:drawable="\@drawable/ic_launcher_monochrome"/>\n!' "$launcher_xml"
fi

echo "Launcher icons regenerated for Android, Android themed icons and iOS."
