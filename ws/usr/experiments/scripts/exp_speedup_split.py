#!/usr/bin/env python3
"""
exp_speedup_split.py — Caliptra speedup measurement with split RTL/firmware compilation.

The key insight: the Verilator RTL binary is identical across tests.
  noFB: $readmemh("program.hex") loads firmware at RUNTIME — binary is shared.
  FB:   firmware objects are linked in, but Verilator's obj_dir caches all RTL
        .o files — only firmware compile + final link changes per test.

Phases (in order):
  1. noFB  RTL compile once      (shared_nofb/)       -> Vcaliptra_top_tb
  2. noFB  firmware compile      (per test, hex only)  -> program.hex etc.
  3. noFB  run                   (per test)
  4. FB    RTL+warmup compile    (shared_fb/, sha256)  -> obj_dir populated
  5. FB    firmware+link         (per test, incremental relink)
  6. FB    run                   (per test)

CSV columns:
  test, nofb_rtl_s, nofb_fw_s, nofb_run_s, fb_rtl_s, fb_fw_link_s, fb_run_s

Values are written to the CSV as soon as each measurement completes.
"""

import csv
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# ─── Tests ────────────────────────────────────────────────────────────────────
TESTS = [
    "smoke_test_strap",
    "smoke_test_hw_config",
    "smoke_test_hmac_kv_ocp_progress",
    "smoke_test_kv_doe",
    "smoke_test_mldsa_kv_ocp_progress",
    "smoke_test_ecc_flow2_kv_ocp_progress",
    "smoke_test_sha256",
    "smoke_test_sha3_regs",
    "smoke_test_sha256_wntz_rand",
    "smoke_test_zeroize_crypto",
    "smoke_test_mbox",
    "smoke_test_doe_kv_ocp_progress",
    "smoke_test_ecc_flow1_kv_ocp_progress",
    "smoke_test_doe_rand",
    "smoke_test_doe_scan",
    "smoke_test_mldsa_zeroize",
    "smoke_test_kv_rules_ocp_lock",
    "smoke_test_doe_cg",
]

# ─── Firmware library deps (mirrors exp_speedup_ahb.py) ───────────────────────
LIB_OF = {
    "smoke_test_sha256":                    "sha256",
    "smoke_test_sha3_regs":                 "sha3",
    "smoke_test_sha256_wntz_rand":          "sha256",
    "smoke_test_strap":                     "",
    "smoke_test_doe_cg":                    "",
    "smoke_test_doe_kv_ocp_progress":       "",
    "smoke_test_ecc_flow1_kv_ocp_progress": "ecc",
    "smoke_test_ecc_flow2_kv_ocp_progress": "ecc",
}

MULTI_LIB_OF = {
    "smoke_test_hmac_kv_ocp_progress": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    "smoke_test_kv_doe": (
        "doe/doe.c ecc/ecc.c hmac/hmac.c sha512/sha512.c sha256/sha256.c "
        "mldsa/mldsa.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "doe ecc hmac sha512 sha256 mldsa keyvault caliptra_rtl_lib",
    ),
    "smoke_test_mldsa_kv_ocp_progress": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_zeroize_crypto": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    "smoke_test_mbox": (
        "soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc caliptra_rtl_lib",
    ),
    "smoke_test_doe_rand":  ("", ""),
    "smoke_test_doe_scan":  ("", ""),
    "smoke_test_mldsa_zeroize": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_kv_rules_ocp_lock": (
        "hmac/hmac.c aes/aes.c ecc/ecc.c mlkem/mlkem.c keyvault/keyvault.c "
        "soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac aes ecc mlkem keyvault soc_ifc caliptra_rtl_lib",
    ),
}

# Tests requiring extra firmware compile flags (RTL binary is still shared)
HW_CONFIG_TESTS = {
    "smoke_test_hw_config": (
        "", "",
        r"FB_FW_CFLAGS=-DCALIPTRA_HWCONFIG_TRNG_EN\ -DCALIPTRA_HWCONFIG_LMS_EN\ -DCALIPTRA_HW_REV_ID=0x0212",
    ),
}

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR    = Path(__file__).resolve().parent
USR           = SCRIPT_DIR.parents[1]          # ws/usr/
WORKSPACE     = USR.parent                     # ws/
CALIPTRA_ROOT = USR / "caliptra-rtl"
MAKEFILE      = CALIPTRA_ROOT / "tools/scripts/Makefile"
LIBROOT       = CALIPTRA_ROOT / "src/integration/test_suites/libs"
WORK          = WORKSPACE / "work_split"
RUNS          = USR / "experiments" / "runs"
RUNS.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

# ─── CSV setup ────────────────────────────────────────────────────────────────
FIELDS = ["test", "nofb_rtl_s", "nofb_fw_s", "nofb_run_s",
          "fb_rtl_s", "fb_fw_link_s", "fb_run_s"]

ts       = datetime.now().strftime("%Y%m%d_%H%M%S")
CSV_PATH = RUNS / f"speedup_split_{ts}.csv"

# In-memory table, flushed to disk after every measurement.
_rows: dict[str, dict] = {t: {"test": t, **{f: "" for f in FIELDS[1:]}}
                           for t in TESTS}

_csv_fh = open(CSV_PATH, "w", newline="")
_writer = csv.DictWriter(_csv_fh, fieldnames=FIELDS)
_writer.writeheader()
_csv_fh.flush()
print(f"CSV: {CSV_PATH}\n")


def _flush_csv() -> None:
    _csv_fh.seek(0)
    _csv_fh.truncate()
    _writer.writeheader()
    for t in TESTS:
        _writer.writerow(_rows[t])
    _csv_fh.flush()


def record(test: str, field: str, value: float) -> None:
    _rows[test][field] = value
    _flush_csv()
    print(f"    {field:20s} = {value:.2f}s")


def record_all(field: str, value: float) -> None:
    """Set the same value for all tests (used for shared RTL compile times)."""
    for t in TESTS:
        _rows[t][field] = value
    _flush_csv()
    print(f"    {field:20s} = {value:.2f}s  (all tests)")


# ─── Shell helpers ────────────────────────────────────────────────────────────
env = os.environ.copy()
env["CALIPTRA_ROOT"]      = str(CALIPTRA_ROOT)
env["CALIPTRA_WORKSPACE"] = str(WORKSPACE)


def sh(cmd: str, cwd: Path = WORK) -> None:
    subprocess.run(cmd, shell=True, cwd=cwd, env=env, check=True)


def timed(cmd: str, cwd: Path = WORK) -> float:
    t0 = time.perf_counter()
    subprocess.run(cmd, shell=True, cwd=cwd, env=env, check=True)
    return round(time.perf_counter() - t0, 2)


def _make(run_dir: Path, target: str, extra: str = "") -> str:
    j = "-j64" if target == "verilator-build" else ""
    return f"make {j} -C {run_dir} -f {MAKEFILE} {extra} {target}"


def _fb_vars(test: str) -> str:
    """Return make variable string for FB_HAL build of this test."""
    base = f"TESTNAME={test}"
    if test in HW_CONFIG_TESTS:
        srcs_rel, dirs_rel, extra_flags = HW_CONFIG_TESTS[test]
        srcs = " ".join(f"{LIBROOT}/{s}" for s in srcs_rel.split()) if srcs_rel else ""
        dirs = " ".join(f"{LIBROOT}/{d}" for d in dirs_rel.split()) if dirs_rel else ""
        return (f'{base} FB_HAL=1 {extra_flags} '
                f'"FB_FW_LIB_SRCS={srcs}" "FB_FW_LIB_DIRS={dirs}"')
    if test in MULTI_LIB_OF:
        srcs_rel, dirs_rel = MULTI_LIB_OF[test]
        srcs = " ".join(f"{LIBROOT}/{s}" for s in srcs_rel.split())
        dirs = " ".join(f"{LIBROOT}/{d}" for d in dirs_rel.split())
        return (f'{base} FB_HAL=1 '
                f'"FB_FW_LIB_SRCS={srcs}" "FB_FW_LIB_DIRS={dirs}"')
    lib = LIB_OF.get(test, "")
    if lib:
        return (f"{base} FB_HAL=1 "
                f"FB_FW_LIB_SRCS={LIBROOT}/{lib}/{lib}.c "
                f"FB_FW_LIB_DIRS={LIBROOT}/{lib}")
    return f'{base} FB_HAL=1 FB_FW_LIB_SRCS="" FB_FW_LIB_DIRS=""'


# ─── Phase 1: noFB RTL compile once ──────────────────────────────────────────
print("=" * 60)
print("Phase 1: noFB RTL compile (once, shared binary)")
print("=" * 60)

SHARED_NOFB = WORK / "shared_nofb"
SHARED_NOFB.mkdir(exist_ok=True)
SHARED_NOFB_BIN = SHARED_NOFB / "obj_dir" / "Vcaliptra_top_tb"

# Build firmware for the placeholder test so the Makefile target chain works,
# then wipe obj_dir and time only the RTL Verilator build.
sh(_make(SHARED_NOFB, "program.hex", "TESTNAME=smoke_test_sha256"))
sh(f"rm -rf {SHARED_NOFB}/obj_dir {SHARED_NOFB}/verilator-build")
nofb_rtl_s = timed(_make(SHARED_NOFB, "verilator-build", "TESTNAME=smoke_test_sha256"))
print(f"  noFB RTL compile: {nofb_rtl_s:.2f}s")
record_all("nofb_rtl_s", nofb_rtl_s)
assert SHARED_NOFB_BIN.exists(), f"Binary not found: {SHARED_NOFB_BIN}"

# ─── Phase 2: noFB firmware compile per test ──────────────────────────────────
print("\n" + "=" * 60)
print("Phase 2: noFB firmware compile (per test, hex only)")
print("=" * 60)

NOFB_DIRS: dict[str, Path] = {}
for test in TESTS:
    print(f"  [{test}]")
    run_dir = WORK / f"{test}_nofb"
    run_dir.mkdir(exist_ok=True)
    NOFB_DIRS[test] = run_dir
    t_fw = timed(_make(run_dir, "program.hex", f"TESTNAME={test}"))
    record(test, "nofb_fw_s", t_fw)

# ─── Phase 3: noFB run per test ───────────────────────────────────────────────
print("\n" + "=" * 60)
print("Phase 3: noFB run (shared binary, per-test hex files)")
print("=" * 60)

for test in TESTS:
    print(f"  [{test}]")
    run_dir = NOFB_DIRS[test]
    # Symlink shared binary into the test's hex directory
    bin_link = run_dir / "Vcaliptra_top_tb"
    bin_link.unlink(missing_ok=True)
    bin_link.symlink_to(SHARED_NOFB_BIN)
    t_run = timed(f"./{bin_link.name}", cwd=run_dir)
    record(test, "nofb_run_s", t_run)

# ─── Phase 4: FB RTL compile once (warm-up with sha256) ───────────────────────
print("\n" + "=" * 60)
print("Phase 4: FB RTL compile (once, shared obj_dir, warm-up)")
print("=" * 60)

SHARED_FB = WORK / "shared_fb"
SHARED_FB.mkdir(exist_ok=True)
SHARED_FB_BIN = SHARED_FB / "obj_dir" / "Vcaliptra_top_tb"
FB_BINS: dict[str, Path] = {}   # saved copy of binary per test after Phase 5

# Use smoke_test_sha256 to warm up obj_dir (fast firmware, minimal link overhead).
# This measures the one-time RTL compile cost: Verilator C++ generation +
# compilation of all RTL objects + link. Subsequent tests reuse these objects.
warmup_vars = _fb_vars("smoke_test_sha256")
sh(_make(SHARED_FB, "program.hex", warmup_vars))
sh(f"rm -rf {SHARED_FB}/obj_dir {SHARED_FB}/verilator-build {SHARED_FB}/.fbfw_built")
fb_rtl_s = timed(_make(SHARED_FB, "verilator-build", warmup_vars))
print(f"  FB RTL+warmup compile: {fb_rtl_s:.2f}s")
record_all("fb_rtl_s", fb_rtl_s)
assert SHARED_FB_BIN.exists(), f"Binary not found: {SHARED_FB_BIN}"

# ─── Phase 5: FB firmware+link per test (truly incremental) ───────────────────
# Strategy: skip Verilator entirely. The generated Makefile in obj_dir exposes
# VM_USER_LDLIBS for the firmware objects. We:
#   (a) compile only the test's firmware .c files (the .fbfw_built make target)
#   (b) run `make -C obj_dir Vcaliptra_top_tb VM_USER_LDLIBS="new_fw_objs"`
# This reuses all RTL .o files and only runs the final link step (~1-2s).
print("\n" + "=" * 60)
print("Phase 5: FB firmware+link (truly incremental — firmware compile + link only)")
print("=" * 60)

OBJ_DIR = SHARED_FB / "obj_dir"


def _fw_objs(test: str, build_dir: Path) -> list[str]:
    """Return the list of firmware .o paths that the warmup Makefile used,
    substituted for this test's specific files."""
    vars_ = _fb_vars(test)
    # Parse FB_FW_LIB_SRCS and the test .c from vars_ to compute .o names.
    # Simpler: run make in dry-run mode to print the .fbfw_built recipe.
    # Even simpler: mirror the Makefile naming: fbfw_<basename>.o
    srcs: list[str] = []
    # Test source
    test_dir = CALIPTRA_ROOT / "src/integration/test_suites" / test
    srcs.append(str(test_dir / f"{test}.c"))
    # Library sources
    if test in HW_CONFIG_TESTS:
        srcs_rel = HW_CONFIG_TESTS[test][0]
    elif test in MULTI_LIB_OF:
        srcs_rel = MULTI_LIB_OF[test][0]
    else:
        lib = LIB_OF.get(test, "")
        srcs_rel = f"{lib}/{lib}.c" if lib else ""
    if srcs_rel:
        for s in srcs_rel.split():
            srcs.append(str(LIBROOT / s))
    # FB harness sources (always included)
    for fb_src in ["fb_printf.c", "fb_caliptra_isr.c"]:
        srcs.append(str(Path("/home/usr/ws/usr/firebridge") / fb_src))
    return [str(build_dir / f"fbfw_{Path(s).stem}.o") for s in srcs]


for test in TESTS:
    print(f"  [{test}]")
    vars_ = _fb_vars(test)

    # (a) Compile firmware .c → .o  (no Verilator, no RTL recompile)
    (SHARED_FB / ".fbfw_built").unlink(missing_ok=True)
    sh(_make(SHARED_FB, "program.hex", vars_))

    t0 = time.perf_counter()
    sh(_make(SHARED_FB, f"{SHARED_FB}/.fbfw_built", vars_))

    # (b) Link only: override VM_USER_LDLIBS with this test's firmware objects
    fw_objs = " ".join(_fw_objs(test, SHARED_FB))
    sh(f'make -C {OBJ_DIR} -f Vcaliptra_top_tb.mk Vcaliptra_top_tb '
       f'VM_USER_LDLIBS="{fw_objs}"')
    t_link = round(time.perf_counter() - t0, 2)

    record(test, "fb_fw_link_s", t_link)

    # Save binary for Phase 6
    saved = WORK / f"{test}_fb_bin"
    shutil.copy2(SHARED_FB_BIN, saved)
    FB_BINS[test] = saved

# ─── Phase 6: FB run per test ─────────────────────────────────────────────────
print("\n" + "=" * 60)
print("Phase 6: FB run (per-test binary)")
print("=" * 60)

# The TB's $readmemh checks whether program.hex exists before reading it,
# so FB runs are safe in any directory. We run from the noFB hex directory
# so console output and any TB file writes land in a consistent place.
for test in TESTS:
    print(f"  [{test}]")
    run_dir = NOFB_DIRS[test]   # already has program.hex / dccm.hex / iccm.hex
    t_run = timed(str(FB_BINS[test]), cwd=run_dir)
    record(test, "fb_run_s", t_run)

# ─── Summary ──────────────────────────────────────────────────────────────────
_csv_fh.close()
print("\n" + "=" * 60)
print("Done.")
print(f"CSV: {CSV_PATH}")

# Quick aggregate
rows = list(_rows.values())
def s(col): return sum(float(r[col]) for r in rows if r[col] != "")

print(f"\nAggregates across {len(TESTS)} tests:")
print(f"  noFB RTL compile (once):    {nofb_rtl_s:.1f}s")
print(f"  noFB fw compile  (sum):     {s('nofb_fw_s'):.1f}s")
print(f"  noFB run         (sum):     {s('nofb_run_s'):.1f}s")
print(f"  FB  RTL compile  (once):    {fb_rtl_s:.1f}s")
print(f"  FB  fw+link      (sum):     {s('fb_fw_link_s'):.1f}s")
print(f"  FB  run          (sum):     {s('fb_run_s'):.1f}s")
print(f"\n  Old total compile (est):    {(nofb_rtl_s + fb_rtl_s) * len(TESTS):.0f}s "
      f"({(nofb_rtl_s + fb_rtl_s) * len(TESTS) / 3600:.1f}h) if each was a full build")
print(f"  New total compile (actual): {nofb_rtl_s + fb_rtl_s + s('nofb_fw_s') + s('fb_fw_link_s'):.0f}s")
