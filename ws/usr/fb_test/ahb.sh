#!/usr/bin/env bash
set -euo pipefail

fb_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$fb_root/.." && pwd)"
export CALIPTRA_WORKSPACE="${CALIPTRA_WORKSPACE:-$workspace_root}"

run_dir="$CALIPTRA_WORKSPACE/work/fb_ahb_selfcheck"
rm -rf "$run_dir"
mkdir -p "$run_dir"

echo "### FB_AHB: selfcheck"
(
  cd "$run_dir"
  verilator --cc --timing \
    --top-module ahb_selfcheck_tb \
    -I"$fb_root/firebridge" \
    -CFLAGS "-std=c++17 -I$fb_root/firebridge" \
    "$fb_root/firebridge/fb_ahb_vip.sv" \
    "$fb_root/fb_test/ahb_selfcheck.sv" \
    --exe "$fb_root/fb_test/ahb_selfcheck_main.cpp" \
          "$fb_root/fb_test/ahb_selfcheck.cpp"
  make -C obj_dir -f Vahb_selfcheck_tb.mk -j"$(nproc)"
  ./obj_dir/Vahb_selfcheck_tb
)

echo "### FB_AHB: completed"
