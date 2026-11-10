#!/usr/bin/env bash
# Puts Flapjaw's small engine (built by .github/workflows/engine.yml from tools/engine) into
# the installed Android build template. Godot's release engine is packed in
# libs/release/godot-lib.template_release.aar as jni/<abi>/libgodot_android.so; this replaces
# the arm64 one and drops the other ABIs (the export only ships arm64). The aar's Java side
# stays as it is, so the engine must come from the same Godot release: checked here.
#
#   tools/ci/swap_android_engine.sh <engine dir> <android/build> <godot version>
set -euo pipefail

engine_dir="$1"
build_dir="$2"
want_version="$3"

so="$engine_dir/libgodot_android.so"
aar="$build_dir/libs/release/godot-lib.template_release.aar"
test -f "$so" || { echo "::error::$so is missing." >&2; exit 1; }
test -f "$aar" || { echo "::error::$aar is missing: install the Android build template first." >&2; exit 1; }
# Absolute: the zip below runs from another directory.
aar="$(cd "$(dirname "$aar")" && pwd)/$(basename "$aar")"

got_version="$(cat "$engine_dir/godot_version.txt")"
if [ "$got_version" != "$want_version" ]; then
  echo "::error::The small engine is Godot $got_version but the export uses $want_version. Update godot_version in the workflow's engine job." >&2
  exit 1
fi

before="$(unzip -l "$aar" | grep 'jni/' || true)"
echo "Engine in the template before:"; echo "$before"

work="$(mktemp -d)"
mkdir -p "$work/jni/arm64-v8a"
cp "$so" "$work/jni/arm64-v8a/libgodot_android.so"
# Keep the template's other arm64 libraries (libc++_shared.so); drop the other ABIs.
zip -q -d "$aar" 'jni/armeabi-v7a/*' 'jni/x86/*' 'jni/x86_64/*' 2>/dev/null || true
(cd "$work" && zip -q "$aar" jni/arm64-v8a/libgodot_android.so)
rm -rf "$work"

echo "Engine in the template now:"; unzip -l "$aar" | grep 'jni/'
