#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="/Applications/CMake.app/Contents/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
SDK=${TH11_SDK:-iphoneos}
case "$SDK" in
  iphoneos) ARCH=arm64;;
  iphonesimulator) ARCH=$(uname -m);;
  *) echo 'Unsupported Apple SDK' >&2; exit 2;;
esac
BUILD=${TH11_BUILD_DIR:-$ROOT/.local/build-$SDK}
python3 "$ROOT/ios/tools/patch_sdl_uikit.py" "${TH11_DEPENDENCIES:-$ROOT/.local/dependencies}/SDL"
CONFIGURE_ARGS=(-S "$ROOT/ios" -B "$BUILD" -G Xcode)
if [ -n "${TH11_PROBE_CACHE:-}" ]; then CONFIGURE_ARGS+=(-C "$TH11_PROBE_CACHE"); fi
cmake "${CONFIGURE_ARGS[@]}" \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DTH11_DEPENDENCIES="${TH11_DEPENDENCIES:-$ROOT/.local/dependencies}" \
  -DTH11_ASSETS="${TH11_ASSETS:-$ROOT/.local/assets}" \
  -DTH11_BUILD_NUMBER="${TH11_BUILD_NUMBER:-1}" \
  -DTH11_DIAGNOSTICS="${TH11_DIAGNOSTICS:-OFF}"
cmake --build "$BUILD" --config RelWithDebInfo --target th11 -- -quiet -jobs "${TH11_BUILD_JOBS:-3}"
# Resource-only edits do not relink the executable; refresh them on every run.
cmake -E copy_directory "${TH11_ASSETS:-$ROOT/.local/assets}" "$BUILD/RelWithDebInfo-$SDK/th11.app/assets"
cmake -E copy_directory "$ROOT/ios/licenses" "$BUILD/RelWithDebInfo-$SDK/th11.app/licenses"
echo "Native bundle: $BUILD/RelWithDebInfo-$SDK/th11.app"
