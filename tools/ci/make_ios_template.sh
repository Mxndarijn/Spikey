#!/usr/bin/env bash
# Makes Flapjaw's iOS export template: Godot's stock ios.zip with the release engine for
# devices (libgodot.ios.release.xcframework/ios-arm64) replaced by the small engine that
# .github/workflows/engine.yml builds from tools/engine. Everything else in the template (the
# Xcode project, the debug engine, the simulator slices) stays stock. The engine must come
# from the same Godot release as the template: checked here.
#
#   tools/ci/make_ios_template.sh <engine dir> <stock ios.zip> <output zip> <godot version>
set -euo pipefail

engine_dir="$1"
stock_zip="$2"
out_zip="$3"
want_version="$4"

lib="$engine_dir/libgodot.a"
test -f "$lib" || { echo "::error::$lib is missing." >&2; exit 1; }
test -f "$stock_zip" || { echo "::error::$stock_zip is missing." >&2; exit 1; }

got_version="$(cat "$engine_dir/godot_version.txt")"
if [ "$got_version" != "$want_version" ]; then
  echo "::error::The small engine is Godot $got_version but the export uses $want_version. Update godot_version in the workflow's engine job." >&2
  exit 1
fi

work="$(mktemp -d)"
unzip -q "$stock_zip" -d "$work"
target="$(find "$work" -path '*libgodot.ios.release.xcframework/ios-arm64/*.a' | head -n1)"
if [ -z "$target" ]; then
  echo "::error::No device release engine in $stock_zip. Its layout:" >&2
  find "$work" -maxdepth 3 | sed "s|$work/||" >&2
  exit 1
fi
echo "Replacing ${target#"$work"/} ($(wc -c < "$target") bytes) with the small engine ($(wc -c < "$lib") bytes)"
cp "$lib" "$target"

out_abs="$(cd "$(dirname "$out_zip")" && pwd)/$(basename "$out_zip")"
rm -f "$out_abs"
(cd "$work" && zip -q -r -y "$out_abs" .)
rm -rf "$work"
echo "Wrote $out_abs"
