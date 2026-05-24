#!/usr/bin/env python3
"""Sweep Caliptra tests: compare Firebridge AXI vs standard verilator compile+run times."""

import subprocess, time, csv, shutil, os
from pathlib import Path
from datetime import datetime

# ── Knobs ────────────────────────────────────────────────────────────────────
TESTS = [
    "smoke_test_sha256",
    "smoke_test_sha512",
    "smoke_test_sha3",
    "smoke_test_hmac",
    "smoke_test_datavault_basic",
    "smoke_test_dma_aes_gcm_short_1_dword",
    "smoke_test_dma",
]
# ─────────────────────────────────────────────────────────────────────────────

USR          = Path(__file__).resolve().parents[2]   # ws/usr/
WORKSPACE    = USR.parent                             # ws/
CALIPTRA_ROOT = USR / "caliptra-rtl"
MAKEFILE     = CALIPTRA_ROOT / "tools/scripts/Makefile"
WORK         = WORKSPACE / "work"
RUNS         = USR / "experiments" / "runs"
RUNS.mkdir(parents=True, exist_ok=True)

csv_path = RUNS / f"speedup_axi_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
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

    run_fb   = WORK / f"{test}_fb_axi"
    run_nofb = WORK / f"{test}_no_fb"
    for d in [run_fb, run_nofb]:
        d.mkdir(parents=True, exist_ok=True)

    base_vars = f"TESTNAME={test}"
    fb_vars   = f"{base_vars} FB_AXI=1"

    # ── Firmware (untimed, shared defines.h) ─────────────────────────────────
    print("[setup] building firmware...")
    sh(make(run_nofb, "program.hex", base_vars))
    sh(make(run_fb,   "program.hex", fb_vars))

    # ── Firebridge compile ───────────────────────────────────────────────────
    sh(f"rm -rf {run_fb}/obj_dir {run_fb}/verilator-build "
       f"{run_fb}/verilator_build.log {run_fb}/verilator_make.log")
    print("[FB] compile...")
    fb_compile = timed(make(run_fb, "verilator-build", fb_vars))
    print(f"[FB] compile: {fb_compile}s")

    print("[FB] run...")
    fb_run = timed(f"{run_fb}/obj_dir/Vcaliptra_top_tb +CLP_REGRESSION",
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

    row = {"test":         test,
           "fb_compile_s":   round(fb_compile,   2),
           "fb_run_s":       round(fb_run,        2),
           "nofb_compile_s": round(nofb_compile,  2),
           "nofb_run_s":     round(nofb_run,       2)}
    csv_w.writerow(row)
    csv_f.flush()
    print(row)

csv_f.close()
print(f"\nSaved: {csv_path}")
