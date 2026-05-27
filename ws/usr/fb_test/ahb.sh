#!/usr/bin/env bash
set -euo pipefail

# Runs all AHB-Lite-only FireBridge tests (no VeeR, no interrupts):
#   - selfcheck : fb_ahb_vip drives a toy AHB memory (RTL sanity of the VIP)
#   - sha256    : fb_ahb_vip drives the real Caliptra sha256_ctrl AHB slave
#                 and the C firmware self-checks SHA256("abc").
#
# Usage: ./ahb.sh [test ...]   (default: all)

fb_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$fb_root/.." && pwd)"
export CALIPTRA_WORKSPACE="${CALIPTRA_WORKSPACE:-$workspace_root}"
export CALIPTRA_ROOT="${CALIPTRA_ROOT:-$fb_root/caliptra-rtl}"

common_cflags="-std=c++17 -I$fb_root/firebridge -DAHB_SIM"

run_selfcheck() {
  local run_dir="$CALIPTRA_WORKSPACE/work/fb_ahb_selfcheck"
  rm -rf "$run_dir"; mkdir -p "$run_dir"
  echo "### FB_AHB: selfcheck"
  (
    cd "$run_dir"
    verilator --cc --timing \
      --top-module ahb_selfcheck_tb \
      -I"$fb_root/firebridge" \
      -CFLAGS "$common_cflags" \
      "$fb_root/firebridge/fb_ahb_vip.sv" \
      "$fb_root/fb_test/ahb_selfcheck.sv" \
      --exe "$fb_root/fb_test/ahb_selfcheck_main.cpp" \
            "$fb_root/fb_test/ahb_selfcheck.cpp"
    make -C obj_dir -f Vahb_selfcheck_tb.mk -j"$(nproc)"
    ./obj_dir/Vahb_selfcheck_tb
  )
}

run_sha256() {
  local run_dir="$CALIPTRA_WORKSPACE/work/fb_ahb_sha256"
  local rtl="$CALIPTRA_ROOT/src"
  rm -rf "$run_dir"; mkdir -p "$run_dir"
  echo "### FB_AHB: sha256"
  (
    cd "$run_dir"
    verilator --cc --timing \
      --top-module sha256_ahb_tb \
      -Wno-fatal \
      +define+RV_OPENSOURCE \
      -I"$fb_root/firebridge" \
      -I"$rtl/integration/rtl" \
      -I"$rtl/libs/rtl" \
      -I"$rtl/sha256/rtl" \
      -CFLAGS "$common_cflags -DFB_AHB_DATA64" \
      "$rtl/integration/rtl/config_defines.svh" \
      "$rtl/libs/rtl/caliptra_macros.svh" \
      "$rtl/libs/rtl/caliptra_sva.svh" \
      "$rtl/libs/rtl/ahb_defines_pkg.sv" \
      "$rtl/libs/rtl/ahb_slv_sif.sv" \
      "$rtl/sha256/rtl/sha256_reg_pkg.sv" \
      "$rtl/sha256/rtl/sha256_params_pkg.sv" \
      "$rtl/sha256/rtl/sha256_ctrl.sv" \
      "$rtl/sha256/rtl/sha256.sv" \
      "$rtl/sha256/rtl/sha256_core.v" \
      "$rtl/sha256/rtl/sha256_k_constants.v" \
      "$rtl/sha256/rtl/sha256_w_mem.v" \
      "$rtl/sha256/rtl/sha256_reg.sv" \
      "$fb_root/firebridge/fb_ahb_vip.sv" \
      "$fb_root/fb_test/sha256_ahb_tb.sv" \
      --exe "$fb_root/fb_test/sha256_ahb_main.cpp" \
            "$fb_root/fb_test/sha256_ahb_fw.cpp"
    make -C obj_dir -f Vsha256_ahb_tb.mk -j"$(nproc)"
    ./obj_dir/Vsha256_ahb_tb
  )
}

tests=(selfcheck sha256)
if [[ $# -gt 0 ]]; then
  tests=("$@")
fi

for t in "${tests[@]}"; do
  "run_$t"
done

echo "### FB_AHB: completed ${#tests[@]} test(s)"
