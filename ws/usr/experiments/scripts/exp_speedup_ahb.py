#!/usr/bin/env python3
"""Sweep Caliptra AHB tests via the FireBridge HAL (Mode B, VeeR bypassed): the
UNMODIFIED upstream test firmware runs natively over the internal AHB (FB_HAL=1).
Compares FB-HAL vs standard verilator compile+run times."""

import subprocess, time, csv, os, sys
from pathlib import Path
from datetime import datetime

# ── Knobs ────────────────────────────────────────────────────────────────────
# test -> crypto lib it pulls in (compiled natively for the HAL build). Add a
# row once that lib's deref loops + wfi/nop are HAL-converted (see the
# "add a test" recipe in engineering_lessons/caliptra_progress.md).
LIB_OF = {
    # T0 (original, bespoke C routine measured earlier)
    "smoke_test_sha256": "sha256",
    "smoke_test_sha512": "sha512",
    "smoke_test_hmac":   "hmac",
    # T1 — added 2026-05-27, all HAL (unmodified firmware + minimal lib cleanup)
    "smoke_test_sha512_restore":  "sha512",
    "smoke_test_sha256_wntz":     "sha256",
    "smoke_test_sha256_wntz_rand": "sha256",
    "smoke_test_sha3_regs":       "sha3",
    "smoke_test_zeroize_crypto":  "hmac",
    # smoke_test_hmac_errortrigger needs 2 libs: hmac + caliptra_rtl_lib.
    # The single-lib LIB_OF pattern doesn't cover it; run manually:
    # make ... TESTNAME=smoke_test_hmac_errortrigger FB_HAL=1 \
    #   "FB_FW_LIB_SRCS=.../hmac/hmac.c .../caliptra_rtl_lib/caliptra_rtl_lib.c" \
    #   "FB_FW_LIB_DIRS=.../hmac .../caliptra_rtl_lib"
}
TESTS = list(LIB_OF)
if len(sys.argv) > 1:           # optional subset: exp_speedup_ahb.py test1 test2 ...
    TESTS = sys.argv[1:]
# ─────────────────────────────────────────────────────────────────────────────

USR           = Path(__file__).resolve().parents[2]   # ws/usr/
WORKSPACE     = USR.parent                             # ws/
CALIPTRA_ROOT = USR / "caliptra-rtl"
MAKEFILE      = CALIPTRA_ROOT / "tools/scripts/Makefile"
LIBROOT       = CALIPTRA_ROOT / "src/integration/test_suites/libs"
WORK          = WORKSPACE / "work"
RUNS          = USR / "experiments" / "runs"
RUNS.mkdir(parents=True, exist_ok=True)

csv_path = RUNS / f"speedup_ahb_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
FIELDS = ["test", "fb_compile_s", "fb_run_s", "nofb_compile_s", "nofb_run_s"]

csv_f = open(csv_path, "w", newline="")
csv_w = csv.DictWriter(csv_f, fieldnames=FIELDS)
csv_w.writeheader()
csv_f.flush()

env = os.environ.copy()
env["CALIPTRA_ROOT"] = str(CALIPTRA_ROOT)
env["CALIPTRA_WORKSPACE"] = str(WORKSPACE)


def sh(cmd, cwd=None):
    subprocess.run(cmd, shell=True, cwd=cwd or WORK, check=True, env=env)


def timed(cmd, cwd=None):
    t0 = time.perf_counter()
    subprocess.run(cmd, shell=True, cwd=cwd or WORK, check=True, env=env)
    return round(time.perf_counter() - t0, 2)


def make(run_dir, target, extra=""):
    return f"make -C {run_dir} -f {MAKEFILE} {extra} {target}"


for test in TESTS:
    print(f"\n=== {test} ===")
    WORK.mkdir(parents=True, exist_ok=True)

    run_fb   = WORK / f"{test}_fb_hal"
    run_nofb = WORK / f"{test}_no_fb"
    for d in [run_fb, run_nofb]:
        d.mkdir(parents=True, exist_ok=True)

    lib       = LIB_OF.get(test, test.replace("smoke_test_", ""))
    base_vars = f"TESTNAME={test}"
    fb_vars   = (f"{base_vars} FB_HAL=1 "
                 f"FB_FW_LIB_SRCS={LIBROOT}/{lib}/{lib}.c "
                 f"FB_FW_LIB_DIRS={LIBROOT}/{lib}")

    # ── Firmware (untimed, shared defines.h) ─────────────────────────────────
    print("[setup] building firmware...")
    sh(make(run_nofb, "program.hex", base_vars))
    sh(make(run_fb,   "program.hex", fb_vars))

    # ── FireBridge HAL compile (incl. native firmware objects) ───────────────
    sh(f"rm -rf {run_fb}/obj_dir {run_fb}/verilator-build "
       f"{run_fb}/verilator_build.log {run_fb}/verilator_make.log "
       f"{run_fb}/.fbfw_built {run_fb}/fbfw_*.o")
    print("[FB] compile...")
    fb_compile = timed(make(run_fb, "verilator-build", fb_vars))
    print(f"[FB] compile: {fb_compile}s")

    print("[FB] run...")
    fb_run = timed(f"{run_fb}/obj_dir/Vcaliptra_top_tb",
                   cwd=run_fb)
    print(f"[FB] run: {fb_run}s")

    # ── No-Firebridge compile ────────────────────────────────────────────────
    sh(f"rm -rf {run_nofb}/obj_dir {run_nofb}/verilator-build "
       f"{run_nofb}/verilator_build.log {run_nofb}/verilator_make.log")
    print("[NoFB] compile...")
    nofb_compile = timed(make(run_nofb, "verilator-build", base_vars))
    print(f"[NoFB] compile: {nofb_compile}s")

    print("[NoFB] run...")
    nofb_run = timed(f"{run_nofb}/obj_dir/Vcaliptra_top_tb",
                     cwd=run_nofb)
    print(f"[NoFB] run: {nofb_run}s")

    row = {"test":           test,
           "fb_compile_s":   fb_compile,
           "fb_run_s":       fb_run,
           "nofb_compile_s": nofb_compile,
           "nofb_run_s":     nofb_run}
    csv_w.writerow(row)
    csv_f.flush()
    print(row)

csv_f.close()
print(f"\nSaved: {csv_path}")
