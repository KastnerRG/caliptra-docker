#!/usr/bin/env bash
set -euo pipefail

fb_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$fb_root/.." && pwd)"
export CALIPTRA_ROOT="${CALIPTRA_ROOT:-$fb_root/caliptra-rtl}"
export CALIPTRA_WORKSPACE="${CALIPTRA_WORKSPACE:-$workspace_root}"
export CALIPTRA_PRIM_ROOT="${CALIPTRA_PRIM_ROOT:-$CALIPTRA_ROOT/src/caliptra_prim_generic}"
export CALIPTRA_PRIM_MODULE_PREFIX="${CALIPTRA_PRIM_MODULE_PREFIX:-caliptra_prim_generic}"
export CALIPTRA_AXI4PC_DIR="${CALIPTRA_AXI4PC_DIR:-$CALIPTRA_ROOT/src/integration/tb}"

default_tests=(
  smoke_test_sha256
  smoke_test_sha512
  smoke_test_sha3
  smoke_test_hmac
  smoke_test_datavault_basic
  smoke_test_dma_aes_gcm_short_1_dword
  smoke_test_dma
)

tests=("${default_tests[@]}")
if [[ $# -gt 0 ]]; then
  tests=("$@")
elif [[ -n "${FB_TESTS:-}" ]]; then
  read -r -a tests <<< "$FB_TESTS"
fi

mkdir -p "$CALIPTRA_WORKSPACE/work"

for test in "${tests[@]}"; do
  run_dir="$CALIPTRA_WORKSPACE/work/${test}_fb_axi"
  log="$CALIPTRA_WORKSPACE/work/${test}_fb_axi.log"

  rm -rf "$run_dir"
  mkdir -p "$run_dir"

  echo "### FB_AXI: $test"
  (
    set -o pipefail
    make -C "$run_dir" \
      -f "$CALIPTRA_ROOT/tools/scripts/Makefile" \
      TESTNAME="$test" \
      FB_AXI=1 \
      VERILATOR_RUN_ARGS="+CLP_REGRESSION" \
      verilator 2>&1 | tee "$log"
  )
done

echo "### FB_AXI: completed ${#tests[@]} test(s)"
