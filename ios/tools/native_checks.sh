#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/.local/native-checks"
mkdir -p "$OUT"
FLAGS=(-std=c++17 -O2 -ffp-contract=off -fno-fast-math -fno-strict-aliasing -DTH_NATIVE_PLATFORM=1)
for name in joystick lifecycle touch_policy portrait_touch; do
  clang++ "${FLAGS[@]}" "$ROOT/ios/tests/$name.cpp" -o "$OUT/$name"
  "$OUT/$name"
done
clang++ "${FLAGS[@]}" "$ROOT/ios/tests/ecl_jump.cpp" "$ROOT/th11_web/cpp/game/EclContext.cpp" "$ROOT/th11_web/cpp/game/EclOwner.cpp" "$ROOT/th11_web/cpp/game/EclInterpreter.cpp" "$ROOT/th11_web/cpp/game/EclResource.cpp" -o "$OUT/ecl-jump"
"$OUT/ecl-jump"
if [ "${1:-}" = "--policy-only" ]; then exit 0; fi
python3 "$ROOT/ios/tools/build_native_check.py"
"$OUT/native-game" "$ROOT/.local/assets/game/th11.dat"
