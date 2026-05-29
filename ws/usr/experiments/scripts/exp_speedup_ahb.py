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
# LIB_OF: test -> lib name (single lib, LIBROOT/{lib}/{lib}.c pattern)
# MULTI_LIB_OF: test -> (space-sep srcs, space-sep dirs) for multi-lib tests
# NO_LIB_SET: tests with no crypto lib (just caliptra_defines + printf)
LIB_OF = {
    # T0 (original, bespoke C routine measured earlier)
    "smoke_test_sha256": "sha256",
    "smoke_test_sha512": "sha512",
    "smoke_test_hmac":   "hmac",
    # T1 — added 2026-05-27
    "smoke_test_sha512_restore":  "sha512",
    "smoke_test_sha256_wntz":     "sha256",
    "smoke_test_sha256_wntz_rand": "sha256",
    "smoke_test_sha3_regs":       "sha3",
    "smoke_test_zeroize_crypto":  "hmac",
    # T2 — added 2026-05-28
    "smoke_test_sha3":            "sha3",
    "smoke_test_cshake":          "sha3",
    "smoke_test_datavault_basic": "datavault",
    "smoke_test_datavault_mini":  "datavault",
    "smoke_test_kv_lock_use_mid_read": "",   # no crypto lib — PASS
    "smoke_test_strap":           "",        # no crypto lib — PASS (implicit)
    "smoke_test_sha3_externalmu": "sha3",  # mldsa.h via FB_ALL_LIB_DIRS; no mldsa HW
    "smoke_test_sha3_interrupt":  "sha3",  # T4 — PASS (KMAC IRQ all 3 types)
    "smoke_test_datavault_lock":  "datavault",   # T2 — PASS
    "kv_entry_read_err":          "",            # T3 — PASS (no crypto lib needed)
    "smoke_test_kv_write_scan_mode": "hmac",     # T3 — PASS (HMAC KV scan mode)
    "smoke_test_doe_cg":          "",            # T3 — PASS (implicit; clk_gate stub; no lib)
    "smoke_test_kv_cg":           "",            # T3 — PASS (implicit; clk_gate stub; no lib)
    # OCP-skip tests: OCP_LOCK_MODE_EN=0 → "SS_MODE only" → immediate 0xff pass
    "smoke_test_doe_kv_ocp_progress": "",        # T3 — PASS (OCP=0 skip)
    "smoke_test_ecc_flow1_kv_ocp_progress": "ecc",  # T3 — PASS (OCP=0 skip)
    "smoke_test_ecc_flow2_kv_ocp_progress": "ecc",  # T3 — PASS (OCP=0 skip)
    # smoke_test_kv_rules_ocp_lock needs hmac+aes+ecc+mlkem+keyvault+soc_ifc+caliptra_rtl_lib; see MULTI_LIB_OF
    "smoke_test_kv_securitystate": "",           # T3 — PASS (implicit; rst_count==1 block clean)
    # smoke_test_mldsa_kv_ocp_progress needs mldsa+caliptra_rtl_lib; see MULTI_LIB_OF
    # smoke_test_trng: needs CALIPTRA_INTERNAL_TRNG=1 to run TRNG (otherwise immediately skips)
    # Run manually: make ... TESTNAME=smoke_test_trng FB_HAL=1 CALIPTRA_INTERNAL_TRNG=1 verilator
}

# Multi-lib tests: (FB_FW_LIB_SRCS string, FB_FW_LIB_DIRS string)
MULTI_LIB_OF = {
    # T1
    "smoke_test_hmac_errortrigger": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    # T2
    "pv_hash_zeroize": (
        "sha512/sha512.c keyvault/keyvault.c",
        "sha512 keyvault",
    ),
    # T3 — added 2026-05-28
    "smoke_test_kv_hmac_flow": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    "smoke_test_fw_kv_backtoback_hmac": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    "smoke_test_hek_flow": (
        "doe/doe.c hmac/hmac.c",
        "doe hmac",
    ),
    "smoke_test_doe_rand": (
        "",   # no crypto lib: test uses lsu_* directly
        "",
    ),
    "smoke_test_hmac_kv_ocp_progress": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    "smoke_test_mldsa_kv_ocp_progress": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_kv_doe": (
        "doe/doe.c ecc/ecc.c hmac/hmac.c sha512/sha512.c sha256/sha256.c mldsa/mldsa.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "doe ecc hmac sha512 sha256 mldsa keyvault caliptra_rtl_lib",
    ),
    # T3 — ecc/hmac KV flows
    "smoke_test_kv_hmac_multiblock_flow": (
        "hmac/hmac.c ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac ecc caliptra_rtl_lib",
    ),
    "smoke_test_kv_ecc_flow1": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_kv_ecc_flow2": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_kv_swwe_lock": (
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    "smoke_test_kv_mldsa": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # T3 — ECC standalone tests (no reset commands, no volatile ptr issues)
    "smoke_test_ecc_keygen": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_ecc_sign": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_ecc_verify": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_ecdh": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    # T7 — ML-KEM KV flow (no volatile ptr issues)
    "smoke_test_mlkem_kv": (
        "mlkem/mlkem.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mlkem caliptra_rtl_lib",
    ),
    # T7 — ML-KEM KV OCP progress (OCP=0→SS_MODE skip)
    "smoke_test_mlkem_kv_ocp_progress": (
        "mlkem/mlkem.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mlkem caliptra_rtl_lib",
    ),
    # T7 — ML-KEM all-zero seed (no volatile ptr issues, just mlkem.c)
    "smoke_test_mlkem_all_zero_seed": (
        "mlkem/mlkem.c",
        "mlkem",
    ),
    # T7 — ML-KEM standard test (keygen/encaps/decaps checks, just mlkem.c)
    "smoke_test_mlkem": (
        "mlkem/mlkem.c",
        "mlkem",
    ),
    # T7 — randomized ML-DSA invalid verify
    "randomized_mldsa_invalid_verify": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # T7 — ML-KEM locked API test
    "smoke_test_mlkem_locked_api": (
        "mlkem/mlkem.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mlkem caliptra_rtl_lib",
    ),
    # T7 — ML-DSA tests with no volatile ptr or reset issues
    "mldsa_pcr_inject_failure": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "randomized_pcr_mldsa_signing": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # T3 — KV parallel access (all crypto in parallel, HW-dominated)
    "smoke_test_kv_parallel_access": (
        "ecc/ecc.c hmac/hmac.c sha512/sha512.c sha256/sha256.c doe/doe.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc hmac sha512 sha256 doe caliptra_rtl_lib",
    ),
    # T7 — ML-DSA KAT and random tests (no volatile ptr issues)
    "smoke_test_mldsa_kat": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_mldsa_keygen_sign_vfy_rand": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_mldsa_keygen_standalone_sign_vfy_rand": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # NOTE: smoke_test_hw_config is handled via HW_CONFIG_TESTS below (needs extra FW_CFLAGS)
    # T7 — mldsa_edge: edge-case inputs with direct MLDSA_CTRL, TB inject 0xd7
    "smoke_test_mldsa_edge": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # T3 — randomized PCR+ECC signing (TB inject privkey, many random ECC sign iterations)
    "randomized_pcr_ecc_signing": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    # T3 — KV crypto chain (DOE→KV, ECC keygen/sign, HMAC, SHA, MLDSA)
    "smoke_test_kv_crypto_flow": (
        "ecc/ecc.c hmac/hmac.c sha512/sha512.c sha256/sha256.c doe/doe.c mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc hmac sha512 sha256 doe mldsa caliptra_rtl_lib",
    ),
    # T7 — smoke_test_mldsa: full keygen+sign+verify flow
    "smoke_test_mldsa": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # T7 — mldsa_locked_api (same fix as mlkem_locked_api)
    "smoke_test_mldsa_locked_api": (
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    # T7 — mldsa_externalmu variants
    "smoke_test_mldsa_externalmu": (
        "mldsa/mldsa.c sha3/sha3.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa sha3 caliptra_rtl_lib",
    ),
    "smoke_test_mldsa_externalmu_keygen_sign_vfy_rand": (
        "mldsa/mldsa.c sha3/sha3.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa sha3 caliptra_rtl_lib",
    ),
    # T4 — QSPI and UART peripheral tests (pass immediately if peripheral not enabled in HW config)
    "smoke_test_qspi": ("", ""),
    "smoke_test_uart": ("", ""),
    # T2 — PCR signing (TB inject sets up ECC key via KV slot, then PCR sign)
    "smoke_test_pcr_signing": (
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    # T2 — PCR zeroize (TB inject: ECC+MLDSA, then zeroize)
    "smoke_test_pcr_zeroize": (
        "ecc/ecc.c mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc mldsa caliptra_rtl_lib",
    ),
    "smoke_test_kv_rules_ocp_lock": (
        "hmac/hmac.c aes/aes.c ecc/ecc.c mlkem/mlkem.c keyvault/keyvault.c soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac aes ecc mlkem keyvault soc_ifc caliptra_rtl_lib",
    ),
    # Warm-reset tests — newly enabled by fb_stdout_ctrl(0xf5/0xf6/0xf7) calling boot_caliptra()
    "smoke_test_doe_scan": ("", ""),            # T3: DOE scan mode, 4 warm resets, no lib
    "smoke_test_wdt": ("", ""),                 # T4: WDT timeout/NMI, 1 warm reset
    "smoke_test_kv_uds_reset": ("", ""),        # T3: UDS KV across warm reset
    "pv_hash_reset": (                           # T2: PCR hash across warm reset
        "sha512/sha512.c keyvault/keyvault.c",
        "sha512 keyvault",
    ),
    "smoke_test_datavault_reset": (              # T2: DV state across warm/cold reset
        "datavault/datavault.c",
        "datavault",
    ),
    "smoke_test_mldsa_zeroize": (               # T7: ML-DSA zeroize (uses warm reset)
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_ecc_errortrigger2": (           # T3: ECC error inject (2 warm resets)
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_ecc_errortrigger3": (           # T3: ECC error inject #3 (2 warm resets)
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_ecc_errortrigger4": (           # T3: ECC error inject #4 (2 warm resets)
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_ecc_errortrigger5": (           # T3: ECC error inject #5 (2 warm resets)
        "ecc/ecc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc caliptra_rtl_lib",
    ),
    "smoke_test_kv_crypto_flow2": (             # T3: crypto chain variant with warm resets
        "ecc/ecc.c hmac/hmac.c sha512/sha512.c sha256/sha256.c doe/doe.c mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "ecc hmac sha512 sha256 doe mldsa caliptra_rtl_lib",
    ),
}

# Tests needing extra FW CFLAGS (e.g. hardware config defines).
# Each entry: test_name -> (lib_srcs, lib_dirs, fw_cflags_extra)
HW_CONFIG_TESTS = {
    "smoke_test_hw_config": ("", "", r"FB_FW_CFLAGS=-DCALIPTRA_HWCONFIG_TRNG_EN\ -DCALIPTRA_HWCONFIG_LMS_EN\ -DCALIPTRA_HW_REV_ID=0x0212"),
}
TESTS = list(LIB_OF) + list(MULTI_LIB_OF) + list(HW_CONFIG_TESTS)
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

    base_vars = f"TESTNAME={test}"
    extra_fw_cflags = ""
    if test in HW_CONFIG_TESTS:
        srcs_rel, dirs_rel, extra_fw_cflags = HW_CONFIG_TESTS[test]
        srcs = " ".join(f"{LIBROOT}/{s}" for s in srcs_rel.split()) if srcs_rel else ""
        dirs = " ".join(f"{LIBROOT}/{d}" for d in dirs_rel.split()) if dirs_rel else ""
        fb_vars = (f'{base_vars} FB_HAL=1 {extra_fw_cflags} '
                   f'"FB_FW_LIB_SRCS={srcs}" '
                   f'"FB_FW_LIB_DIRS={dirs}"')
    elif test in MULTI_LIB_OF:
        srcs_rel, dirs_rel = MULTI_LIB_OF[test]
        srcs = " ".join(f"{LIBROOT}/{s}" for s in srcs_rel.split())
        dirs = " ".join(f"{LIBROOT}/{d}" for d in dirs_rel.split())
        fb_vars = (f'{base_vars} FB_HAL=1 '
                   f'"FB_FW_LIB_SRCS={srcs}" '
                   f'"FB_FW_LIB_DIRS={dirs}"')
    else:
        lib = LIB_OF.get(test, test.replace("smoke_test_", ""))
        if lib:
            fb_vars = (f"{base_vars} FB_HAL=1 "
                       f"FB_FW_LIB_SRCS={LIBROOT}/{lib}/{lib}.c "
                       f"FB_FW_LIB_DIRS={LIBROOT}/{lib}")
        else:
            fb_vars = f'{base_vars} FB_HAL=1 FB_FW_LIB_SRCS="" FB_FW_LIB_DIRS=""'

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
