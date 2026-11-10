#!/usr/bin/env bash
# Firebase (Board alerts) needs Google's "google-services" Gradle plugin, which
# turns google-services.json into the resources Firebase reads at start. Godot's
# Android build template doesn't have it, so this adds it to the installed
# template (android/build/build.gradle). Safe to run twice.
#
#   tools/ci/patch_android_gradle.sh [path/to/build.gradle]
set -euo pipefail

gradle="${1:-android/build/build.gradle}"
version="4.4.4"

if [ ! -f "$gradle" ]; then
  echo "::error::$gradle not found: install the Android build template first." >&2
  exit 1
fi
if grep -q "com.google.gms.google-services" "$gradle"; then
  echo "google-services is already in $gradle"
  exit 0
fi

tmp="$(mktemp)"
{
  # Must be the first thing in the file, before Godot's own buildscript and plugins.
  printf 'buildscript {\n'
  printf '    repositories {\n        google()\n        mavenCentral()\n    }\n'
  printf '    dependencies {\n'
  printf "        classpath 'com.google.gms:google-services:%s'\n" "$version"
  printf '    }\n}\n\n'
  cat "$gradle"
  printf "\napply plugin: 'com.google.gms.google-services'\n"
} > "$tmp"
mv "$tmp" "$gradle"
echo "Added google-services $version to $gradle"
