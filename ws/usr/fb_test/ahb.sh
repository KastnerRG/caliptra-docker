#!/usr/bin/env bash
set -euo pipefail

# Runs the FireBridge AHB tests. Two flavours:
#
# Standalone block-level (Mode C, fast VIP/RTL sanity, no SoC/boot):
#   - selfcheck : fb_ahb_vip drives a toy AHB memory (RTL sanity of the VIP)
#   - sha256    : fb_ahb_vip drives the real Caliptra sha256_ctrl AHB slave
#                 and the C firmware self-checks SHA256("abc").
#
# Full-SoC HAL (Mode B, VeeR bypassed, boot over s_axi, the UNMODIFIED upstream
# test firmware run natively over the internal AHB via the FB HAL, FB_HAL=1):
#   - hal_sha256 / hal_sha512 / hal_hmac : real smoke_test_*.c + crypto lib,
#     each ends with the TB's own "* TESTCASE PASSED".
#
# Usage: ./ahb.sh [test ...]   (default: all)
#   e.g. ./ahb.sh hal_hmac          # one full-SoC HAL test
#        ./ahb.sh selfcheck sha256  # just the fast standalone checks

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

# Full-SoC HAL tests run the real firmware via the main Makefile (FB_HAL=1).
mk="$CALIPTRA_ROOT/tools/scripts/Makefile"
libroot="$CALIPTRA_ROOT/src/integration/test_suites/libs"

run_hal() {  # $1=short label  $2=TESTNAME  $3=crypto lib dir/name
  local short="$1" testname="$2" lib="$3"
  local run_dir="$CALIPTRA_WORKSPACE/work/fb_hal_$short"
  rm -rf "$run_dir"; mkdir -p "$run_dir"
  echo "### FB_HAL: $testname (full-SoC, unmodified firmware over internal AHB)"
  make -C "$run_dir" -f "$mk" \
    CALIPTRA_ROOT="$CALIPTRA_ROOT" CALIPTRA_WORKSPACE="$CALIPTRA_WORKSPACE" \
    TESTNAME="$testname" FB_HAL=1 \
    FB_FW_LIB_SRCS="$libroot/$lib/$lib.c" FB_FW_LIB_DIRS="$libroot/$lib" \
    verilator
}

run_hal_sha256() { run_hal sha256 smoke_test_sha256 sha256; }
run_hal_sha512() { run_hal sha512 smoke_test_sha512 sha512; }
run_hal_hmac()   { run_hal hmac   smoke_test_hmac   hmac;   }

tests=(selfcheck sha256 hal_sha256 hal_sha512 hal_hmac)
if [[ $# -gt 0 ]]; then
  tests=("$@")
fi

for t in "${tests[@]}"; do
  "run_$t"
done

echo "### FB_AHB: completed ${#tests[@]} test(s)"
