#!/usr/bin/env bash
# Turns on R8 (code and resource shrinking) for release builds in the installed Android
# build template (android/build/build.gradle). Godot's template leaves it off; the AdMob,
# Firebase and Play Services code is most of the APK's Java part, and much of it is unused.
# The plugins ship their own keep rules; tools/ci/flapjaw-proguard.pro keeps Godot's Java
# side, which the engine calls by name over JNI. Safe to run twice.
#
#   tools/ci/patch_android_shrink.sh [path/to/build.gradle]
set -euo pipefail

gradle="${1:-android/build/build.gradle}"
rules_src="$(dirname "$0")/flapjaw-proguard.pro"

if [ ! -f "$gradle" ]; then
  echo "::error::$gradle not found: install the Android build template first." >&2
  exit 1
fi
cp "$rules_src" "$(dirname "$gradle")/flapjaw-proguard.pro"
if grep -q "flapjaw-proguard.pro" "$gradle"; then
  echo "R8 is already on in $gradle"
  exit 0
fi

# The first `release {` after `buildTypes {` is the release build type (signingConfigs has
# one too, earlier in the file).
tmp="$(mktemp)"
awk '
  /^[[:space:]]*buildTypes[[:space:]]*\{/ { in_types = 1 }
  {
    print
    if (in_types && !done && $0 ~ /^[[:space:]]*release[[:space:]]*\{/) {
      print "            minifyEnabled true"
      print "            shrinkResources true"
      print "            proguardFiles getDefaultProguardFile(\"proguard-android-optimize.txt\"), \"flapjaw-proguard.pro\""
      done = 1
    }
  }
  END { if (!done) exit 1 }
' "$gradle" > "$tmp" || { echo "::error::No release build type found in $gradle." >&2; rm -f "$tmp"; exit 1; }
mv "$tmp" "$gradle"
echo "Turned on R8 for release builds in $gradle"
