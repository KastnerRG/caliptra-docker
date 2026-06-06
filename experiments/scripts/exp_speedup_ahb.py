#!/usr/bin/env python3
"""Sweep Caliptra AHB tests via the FireBridge HAL (Mode B, VeeR bypassed): the
UNMODIFIED upstream test firmware runs natively over the internal AHB (FB_HAL=1).

Split-compile methodology — the Verilator SoC binary is built ONCE per mode and
reused for every test (it is identical across tests; only the firmware differs):
    no-FB -> shared_nofb/   ("default" BUILD_DIR=$(CURDIR), unmodified RTL —
                             $readmemh("program.hex") loads firmware at runtime)
    FB    -> shared_fb/     (separate dir; FB_HAL=1 — stub VeeR + fb_ahb_vip;
                             firmware is compiled to native objects and linked in)

Per test, only the firmware is rebuilt:
    no-FB: recompile program.hex, run via the shared binary (symlinked in)
    FB:    recompile fbfw_*.o, then an INCREMENTAL relink — `make
           VM_USER_LDLIBS=<new fw objs>` overrides the firmware-object list in
           the generated obj_dir/Vcaliptra_top_tb.mk and only re-runs the final
           link step (~seconds), reusing every cached verilated RTL .o file.

PASS/FAIL is mode-specific (the two modes verdict through different paths):
  no-FB: the SV TB's `* TESTCASE PASSED` / `* TESTCASE FAILED` markers
         (caliptra_top_tb_services.sv, printed unconditionally at $finish).
  FB:    the FB_HAL harness's OWN verdict, printed (and the process exited)
         BEFORE the SV TB's verdict code is ever reached — see run_sim() in
         firebridge/c/ahb.cpp:
           "FB_HAL: TEST PASSED ..."        (firmware sent SEND_STDOUT_CTRL 0xff)
           "FB_HAL: TEST FAILED ..."        (firmware sent SEND_STDOUT_CTRL 0x1)
           "FB_HAL: firmware returned ..."  (no explicit signal — tests like
                                             doe_scan rely on TB assertions
                                             instead; ahb.cpp explicitly treats
                                             a normal return as PASS)

Two distinct speedups are reported (see bottom of this file):
  - "compile once"   : one-time SoC compile + N tests of fw-compile/link/run,
                       summed end to end — the realistic win when the SoC
                       binary is built once and reused for a whole sweep.
  - "compile & link" : per-test firmware compile(+link) time only — isolates
                       the win of FB's incremental relink vs. noFB's full
                       program.hex regeneration, independent of the
                       (amortizable) one-time SoC build.
"""

import argparse, csv, os, shutil, subprocess, sys, time
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
    "smoke_test_kv_mlkem": (
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
    "smoke_test_wdt": ("wdt/wdt.c", "wdt"),              # T4: WDT timeout/NMI, warm reset
    "smoke_test_wdt_rst": ("wdt/wdt.c", "wdt"),          # T4: WDT reset path
    # smoke_test_cg_wdt broken: uses VeeR CSR inline asm (csrwi/csrw) for clk_gate — can't compile on x86
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
    # T7 — MLDSA/MLKEM error triggers
    "smoke_test_mldsa_sign_rnd": (              # T7: MLDSA sign with fixed sign_rnd (upstream fixed vectors)
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_mldsa_errortrigger": (          # T7: MLDSA error injection (privkey loop fixed)
        "mldsa/mldsa.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mldsa caliptra_rtl_lib",
    ),
    "smoke_test_mlkem_errortrigger": (          # T7: ML-KEM error injection
        "mlkem/mlkem.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mlkem caliptra_rtl_lib",
    ),
    "smoke_test_mlkem_shared_key": (            # T7: ML-KEM shared-key check (AES_DATA_DIRECT)
        "mlkem/mlkem.c hmac/hmac.c aes/aes.c keyvault/keyvault.c soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "mlkem hmac aes keyvault soc_ifc caliptra_rtl_lib",
    ),
    "smoke_test_zeroize_crypto": (              # T7: zeroize crypto state
        "hmac/hmac.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "hmac caliptra_rtl_lib",
    ),
    # T5 — AXI DMA tests (M-side AXI to AXI FIFO/SRAM, with warm reset)
    "smoke_test_dma": (                         # T5: basic DMA (AHB↔AXI, mbox, FIFO)
        "soc_ifc/soc_ifc.c",
        "soc_ifc",
    ),
    "smoke_test_dma_aes_gcm": (                 # T5: DMA + AES-GCM encryption
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_short_1_dword": (   # T5: DMA AES-GCM, 1-dword payload
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_short_dword": (     # T5: DMA AES-GCM, short dword
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_cmd_err": (         # T5: DMA AES-GCM command error
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_collision_test": (  # T5: DMA AES-GCM collision
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_rd_enc_axi_err": (  # T5: DMA AES-GCM read enc AXI err
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_wr_enc_axi_err": (  # T5: DMA AES-GCM write enc AXI err
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_gcm_non_gcm_en_dec": (  # T5: DMA AES-GCM non-GCM enc/dec
        "soc_ifc/soc_ifc.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_dma_aes_kv": (                  # T5: DMA + AES-KV (keyvault)
        "soc_ifc/soc_ifc.c hmac/hmac.c aes/aes.c keyvault/keyvault.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc hmac aes keyvault caliptra_rtl_lib",
    ),
    "smoke_test_mbox": (                        # T6: bidirectional mailbox (SOC↔FW)
        "soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc caliptra_rtl_lib",
    ),
    "smoke_test_mbox_cg": (                     # T6: mailbox with clock gating
        "soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc caliptra_rtl_lib",
    ),
    "smoke_test_mbox_byte_read": (              # T6: mailbox SRAM byte-read
        "soc_ifc/soc_ifc.c caliptra_rtl_lib/caliptra_rtl_lib.c",
        "soc_ifc caliptra_rtl_lib",
    ),
}

# Tests needing extra FW CFLAGS (e.g. hardware config defines).
# Each entry: test_name -> (lib_srcs, lib_dirs, fw_cflags_extra)
HW_CONFIG_TESTS = {
    "smoke_test_hw_config": ("", "", r"FB_FW_CFLAGS=-DCALIPTRA_HWCONFIG_TRNG_EN\ -DCALIPTRA_HWCONFIG_LMS_EN\ -DCALIPTRA_HW_REV_ID=0x0212"),
}

# Full test set: every test currently passing via FB_HAL per the Done (✅) column
# of engineering_lessons/caliptra_tests.md Table 1 — 73 of the 74 (excludes
# smoke_test_trng, which needs CALIPTRA_INTERNAL_TRNG=1 and a manual run; see the
# note next to its LIB_OF entry above). Each has a LIB_OF / MULTI_LIB_OF /
# HW_CONFIG_TESTS entry above, so the sweep can build+run all of them unattended.
FULL_TESTS = [
    "kv_entry_read_err", "mldsa_pcr_inject_failure", "pv_hash_zeroize",
    "randomized_mldsa_invalid_verify", "randomized_pcr_mldsa_signing",
    "smoke_test_cshake", "smoke_test_datavault_basic", "smoke_test_datavault_lock",
    "smoke_test_datavault_mini", "smoke_test_datavault_reset", "smoke_test_dma",
    "smoke_test_doe_cg", "smoke_test_doe_kv_ocp_progress", "smoke_test_doe_rand",
    "smoke_test_doe_scan", "smoke_test_ecc_errortrigger2", "smoke_test_ecc_errortrigger5",
    "smoke_test_ecc_flow1_kv_ocp_progress", "smoke_test_ecc_flow2_kv_ocp_progress",
    "smoke_test_ecc_keygen", "smoke_test_ecc_sign", "smoke_test_ecc_verify",
    "smoke_test_ecdh", "smoke_test_fw_kv_backtoback_hmac", "smoke_test_hek_flow",
    "smoke_test_hmac", "smoke_test_hmac_errortrigger", "smoke_test_hmac_kv_ocp_progress",
    "smoke_test_hw_config", "smoke_test_kv_cg", "smoke_test_kv_doe",
    "smoke_test_kv_ecc_flow1", "smoke_test_kv_ecc_flow2", "smoke_test_kv_hmac_flow",
    "smoke_test_kv_hmac_multiblock_flow", "smoke_test_kv_lock_use_mid_read",
    "smoke_test_kv_mldsa", "smoke_test_kv_rules_ocp_lock", "smoke_test_kv_securitystate",
    "smoke_test_kv_swwe_lock", "smoke_test_kv_uds_reset", "smoke_test_kv_write_scan_mode",
    "smoke_test_mbox", "smoke_test_mbox_cg", "smoke_test_mldsa",
    "smoke_test_mldsa_errortrigger", "smoke_test_mldsa_externalmu",
    "smoke_test_mldsa_externalmu_keygen_sign_vfy_rand", "smoke_test_mldsa_kat",
    "smoke_test_mldsa_keygen_sign_vfy_rand", "smoke_test_mldsa_keygen_standalone_sign_vfy_rand",
    "smoke_test_mldsa_kv_ocp_progress", "smoke_test_mldsa_sign_rnd", "smoke_test_mlkem",
    "smoke_test_mlkem_errortrigger", "smoke_test_kv_mlkem", "smoke_test_mlkem_kv_ocp_progress",
    "smoke_test_mlkem_shared_key", "smoke_test_pcr_signing", "smoke_test_pcr_zeroize",
    "smoke_test_sha256", "smoke_test_sha256_wntz", "smoke_test_sha256_wntz_rand",
    "smoke_test_sha3", "smoke_test_sha3_externalmu", "smoke_test_sha3_interrupt",
    "smoke_test_sha3_regs", "smoke_test_sha512", "smoke_test_sha512_restore",
    "smoke_test_strap", "smoke_test_wdt", "smoke_test_wdt_rst", "smoke_test_zeroize_crypto",
]

# Representative test set: the SMALLEST subset that still touches every built FB
# feature (AHB/KV/RST/MBOX+BURST/DMA/IRQ — see "FB feature legend" in
# caliptra_tests.md), spans the full honest-speedup range end to end, and covers
# all three firmware build shapes (single-lib / multi-lib / no-lib via LIB_OF /
# MULTI_LIB_OF). Good for a quick sanity sweep; use FULL_TESTS for the real one.
REPRESENTATIVE_TESTS = [
    "smoke_test_sha256",           # T0  AHB              single-lib — baseline; cross-sim (Verilator+VCS) verified
    "smoke_test_doe_rand",         # T3  AHB+KV           no-lib     — DOE→KV decrypt flow
    "smoke_test_kv_uds_reset",     # T3  AHB+KV+RST       no-lib     — warm/cold reset machinery (4 resets)
    "smoke_test_mbox",             # T6  AHB+MBOX+BURST   multi-lib  — bidirectional SOC<->FW mailbox
    "smoke_test_dma",              # T5  AHB+DMA          single-lib — AXI DMA (M-side, m_axi)
    "smoke_test_sha3_interrupt",   # T4  AHB+IRQ          single-lib — real ISR/wfi interrupt path
    "smoke_test_ecc_keygen",       # T3  AHB (HW-bound)   multi-lib  — honest-speedup floor (~1.2x: VeeR overhead ≈ HW time)
    "smoke_test_kv_securitystate", # T3  AHB+KV (OCP-skip) no-lib    — honest-speedup ceiling (~818x: fast-path short-circuit)
]

# Which list to sweep is chosen via --set (default: full); individual TEST
# arguments always win, e.g.:
#   exp_speedup_ahb.py                          -> FULL_TESTS (73 tests)
#   exp_speedup_ahb.py --set repr               -> REPRESENTATIVE_TESTS (8 tests)
#   exp_speedup_ahb.py smoke_test_sha256 ...    -> just the named test(s)
_parser = argparse.ArgumentParser(
    description="Sweep Caliptra AHB tests via the FireBridge HAL — see module docstring.")
_parser.add_argument("tests", nargs="*", metavar="TEST",
                     help="run only these specific test name(s); overrides --set")
_parser.add_argument("--set", choices=["full", "repr"], default="full",
                     help=f"curated list to run when no TEST is given: "
                          f"'full' = all FB_HAL-passing tests ({len(FULL_TESTS)}, default), "
                          f"'repr' = smallest representative subset ({len(REPRESENTATIVE_TESTS)})")
_parser.add_argument("--new-csv", action="store_true",
                     help="start a fresh CSV (discards previous results); "
                          "default is to append to the existing speedup_ahb.csv")
_args = _parser.parse_args()

if _args.tests:
    TESTS = _args.tests
elif _args.set == "repr":
    TESTS = REPRESENTATIVE_TESTS
else:
    TESTS = FULL_TESTS
# ─────────────────────────────────────────────────────────────────────────────

WORKSPACE     = Path(__file__).resolve().parents[2]   # caliptra-docker/ = CALIPTRA_WORKSPACE
CALIPTRA_ROOT = WORKSPACE / "caliptra-rtl"
FB_ROOT       = WORKSPACE / "firebridge"
MAKEFILE      = CALIPTRA_ROOT / "tools/scripts/Makefile"
LIBROOT       = CALIPTRA_ROOT / "src/integration/test_suites/libs"
WORK          = WORKSPACE / "work"
RUNS          = WORKSPACE / "experiments" / "runs"
RUNS.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)

# Two SoC binaries, each Verilated/compiled ONCE and reused for every test
# (the RTL is identical across tests — only the firmware differs):
#   no-FB -> "default" build dir: plain $(CURDIR), unmodified RTL/VeeR
#   FB    -> a separate dir: FB_HAL=1 (stub VeeR + fb_ahb_vip + native fw .o)
SHARED_NOFB     = WORK / "shared_nofb"
SHARED_FB       = WORK / "shared_fb"
SHARED_NOFB.mkdir(exist_ok=True)
SHARED_FB.mkdir(exist_ok=True)
SHARED_NOFB_BIN = SHARED_NOFB / "obj_dir" / "Vcaliptra_top_tb"
SHARED_FB_BIN   = SHARED_FB   / "obj_dir" / "Vcaliptra_top_tb"
FB_OBJ_DIR      = SHARED_FB   / "obj_dir"

RUN_TIMEOUT_S = 1800   # smoke tests finish in seconds; this only guards a hang

env = os.environ.copy()
env["CALIPTRA_ROOT"] = str(CALIPTRA_ROOT)
env["CALIPTRA_WORKSPACE"] = str(WORKSPACE)


def sh(cmd, cwd=None):
    subprocess.run(cmd, shell=True, cwd=cwd or WORK, check=True, env=env)


def timed(cmd, cwd=None):
    t0 = time.perf_counter()
    subprocess.run(cmd, shell=True, cwd=cwd or WORK, check=True, env=env)
    return round(time.perf_counter() - t0, 2)


def _verdict_nofb(text):
    if "TESTCASE PASSED" in text:
        return "PASS"
    if "TESTCASE FAILED" in text:
        return "FAIL"
    return "UNKNOWN"


def _verdict_fb(text):
    # FB_HAL exits (or aborts) BEFORE the SV TB's own verdict print is reached —
    # its own markers are authoritative here (see firebridge/c/ahb.cpp:run_sim).
    if "FB_HAL: TEST FAILED" in text:
        return "FAIL"
    if "FB_HAL: TEST PASSED" in text or "FB_HAL: firmware returned" in text:
        return "PASS"
    return "UNKNOWN"


def run_logged(binary, run_dir, log_name, mode):
    """Run `binary` from `run_dir`, teeing stdout+stderr to `log_name`. Returns
    (elapsed_seconds, 'PASS'|'FAIL'|'TIMEOUT'|'UNKNOWN'). `mode` ('nofb'|'fb')
    selects which verdict markers to look for — see module docstring."""
    log_path = run_dir / log_name
    t0 = time.perf_counter()
    try:
        with open(log_path, "w") as f:
            subprocess.run(f"./{Path(binary).name}", shell=True, cwd=run_dir, env=env,
                           stdout=f, stderr=subprocess.STDOUT, timeout=RUN_TIMEOUT_S)
        verdict = "UNKNOWN"
    except subprocess.TimeoutExpired:
        verdict = "TIMEOUT"
    elapsed = round(time.perf_counter() - t0, 2)
    if verdict != "TIMEOUT":
        text = log_path.read_text(errors="replace")
        verdict = _verdict_fb(text) if mode == "fb" else _verdict_nofb(text)
    return elapsed, verdict


def make(run_dir, target, extra=""):
    # Firmware builds (program.hex) have header-copy race with -j; only verilator-build parallelises safely
    j = "-j64" if target == "verilator-build" else ""
    return f"make {j} -C {run_dir} -f {MAKEFILE} {extra} {target}"


def fb_vars(test):
    """Make-variable string for an FB_HAL build/relink of `test`."""
    base = f"TESTNAME={test}"
    if test in HW_CONFIG_TESTS:
        srcs_rel, dirs_rel, extra_fw_cflags = HW_CONFIG_TESTS[test]
        srcs = " ".join(f"{LIBROOT}/{s}" for s in srcs_rel.split()) if srcs_rel else ""
        dirs = " ".join(f"{LIBROOT}/{d}" for d in dirs_rel.split()) if dirs_rel else ""
        return (f'{base} FB_HAL=1 {extra_fw_cflags} '
                f'"FB_FW_LIB_SRCS={srcs}" "FB_FW_LIB_DIRS={dirs}"')
    if test in MULTI_LIB_OF:
        srcs_rel, dirs_rel = MULTI_LIB_OF[test]
        srcs = " ".join(f"{LIBROOT}/{s}" for s in srcs_rel.split())
        dirs = " ".join(f"{LIBROOT}/{d}" for d in dirs_rel.split())
        return (f'{base} FB_HAL=1 '
                f'"FB_FW_LIB_SRCS={srcs}" "FB_FW_LIB_DIRS={dirs}"')
    lib = LIB_OF.get(test, test.replace("smoke_test_", ""))
    if lib:
        return (f"{base} FB_HAL=1 "
                f"FB_FW_LIB_SRCS={LIBROOT}/{lib}/{lib}.c "
                f"FB_FW_LIB_DIRS={LIBROOT}/{lib}")
    return f'{base} FB_HAL=1 FB_FW_LIB_SRCS="" FB_FW_LIB_DIRS=""'


def fw_objs(test):
    """Mirror the Makefile's FB_FW_OBJS naming (fbfw_<basename>.o in SHARED_FB)
    for `test`'s sources, so we can override VM_USER_LDLIBS for an incremental
    relink without re-running Verilator."""
    srcs = [str(CALIPTRA_ROOT / "src/integration/test_suites" / test / f"{test}.c")]
    if test in HW_CONFIG_TESTS:
        srcs_rel = HW_CONFIG_TESTS[test][0]
    elif test in MULTI_LIB_OF:
        srcs_rel = MULTI_LIB_OF[test][0]
    else:
        lib = LIB_OF.get(test, test.replace("smoke_test_", ""))
        srcs_rel = f"{lib}/{lib}.c" if lib else ""
    if srcs_rel:
        srcs += [str(LIBROOT / s) for s in srcs_rel.split()]
    srcs += [str(FB_ROOT / "c" / n) for n in ("printf.c", "isr.c")]
    return [str(SHARED_FB / f"fbfw_{Path(s).stem}.o") for s in srcs]


# ── CSV setup ─────────────────────────────────────────────────────────────────
FIELDS = ["test",
          "nofb_fw_s", "nofb_run_s", "nofb_result",
          "fb_link_s", "fb_run_s", "fb_result",
          "completed_at"]
csv_path = RUNS / "speedup_ahb.csv"
rows = {t: {"test": t, **{f: "" for f in FIELDS[1:]}} for t in TESTS}

if _args.new_csv:
    csv_path.unlink(missing_ok=True)


def record(test, **kv):
    rows[test].update(kv)
    print(f"    {kv}", flush=True)
    row = rows[test]
    if row.get("nofb_result") and row.get("fb_result"):
        row["completed_at"] = datetime.now().strftime("%Y%m%d_%H%M%S")
        new = not csv_path.exists()
        with open(csv_path, "a", newline="") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
            if new:
                w.writeheader()
            w.writerow(row)


print(f"CSV: {csv_path}  ({'new' if _new_file else 'appending'})", flush=True)
print(f"Tests ({len(TESTS)}): {TESTS}\n", flush=True)

# ── Phase 1: build each SoC binary ONCE ──────────────────────────────────────
warmup = TESTS[0]

print(f"{'='*70}\n[1/3] no-FB SoC compile — ONCE, default build dir: {SHARED_NOFB}\n{'='*70}")
sh(make(SHARED_NOFB, "program.hex", f"TESTNAME={warmup}"))
sh(f"rm -rf {SHARED_NOFB}/obj_dir {SHARED_NOFB}/verilator-build "
   f"{SHARED_NOFB}/verilator_build.log {SHARED_NOFB}/verilator_make.log")
nofb_soc_s = timed(make(SHARED_NOFB, "verilator-build", f"TESTNAME={warmup}"))
print(f"  noFB SoC compile (once): {nofb_soc_s}s")
assert SHARED_NOFB_BIN.exists(), f"Binary not found: {SHARED_NOFB_BIN}"

print(f"\n{'='*70}\n[2/3] FB SoC compile — ONCE, separate build dir: {SHARED_FB}\n{'='*70}")
warmup_vars = fb_vars(warmup)
sh(make(SHARED_FB, "program.hex", warmup_vars))
sh(f"rm -rf {SHARED_FB}/obj_dir {SHARED_FB}/verilator-build "
   f"{SHARED_FB}/verilator_build.log {SHARED_FB}/verilator_make.log "
   f"{SHARED_FB}/.fbfw_built {SHARED_FB}/fbfw_*.o")
fb_soc_s = timed(make(SHARED_FB, "verilator-build", warmup_vars))
print(f"  FB SoC compile (once, incl. {warmup} firmware warm-up): {fb_soc_s}s")
assert SHARED_FB_BIN.exists(), f"Binary not found: {SHARED_FB_BIN}"

# ── Phase 2: per-test compile, link, run ─────────────────────────────────────
print(f"\n{'='*70}\n[3/3] per-test compile/link/run  ({len(TESTS)} tests)\n{'='*70}")

for test in TESTS:
    print(f"\n--- {test} ---", flush=True)
    run_dir = WORK / f"{test}_split"
    run_dir.mkdir(exist_ok=True)
    base_vars = f"TESTNAME={test}"

    # ── no-FB: recompile firmware -> program.hex; run via the shared binary ──
    try:
        t_fw = timed(make(run_dir, "program.hex", base_vars), cwd=run_dir)
        bin_link = run_dir / "Vcaliptra_top_tb_nofb"
        bin_link.unlink(missing_ok=True)
        bin_link.symlink_to(SHARED_NOFB_BIN)
        t_run, result = run_logged(bin_link, run_dir, "nofb_run.log", mode="nofb")
        record(test, nofb_fw_s=t_fw, nofb_run_s=t_run, nofb_result=result)
        print(f"  noFB: fw={t_fw}s  run={t_run}s  [{result}]", flush=True)
    except subprocess.CalledProcessError as e:
        record(test, nofb_fw_s=-1, nofb_run_s=-1, nofb_result="BUILD_ERROR")
        print(f"  noFB: BUILD ERROR ({e})", flush=True)

    # ── FB: recompile fbfw_*.o, then an incremental relink-only step ─────────
    try:
        vars_ = fb_vars(test)
        sh(make(SHARED_FB, "program.hex", vars_))
        (SHARED_FB / ".fbfw_built").unlink(missing_ok=True)

        t0 = time.perf_counter()
        sh(make(SHARED_FB, str(SHARED_FB / ".fbfw_built"), vars_))
        objs = " ".join(fw_objs(test))
        sh(f'make -C {FB_OBJ_DIR} -f Vcaliptra_top_tb.mk Vcaliptra_top_tb '
           f'VM_USER_LDLIBS="{objs}"')
        t_link = round(time.perf_counter() - t0, 2)

        fb_bin = run_dir / "Vcaliptra_top_tb_fb"
        shutil.copy2(SHARED_FB_BIN, fb_bin)
        t_run, result = run_logged(fb_bin, run_dir, "fb_run.log", mode="fb")
        record(test, fb_link_s=t_link, fb_run_s=t_run, fb_result=result)
        print(f"  FB:   link={t_link}s  run={t_run}s  [{result}]", flush=True)
    except subprocess.CalledProcessError as e:
        record(test, fb_link_s=-1, fb_run_s=-1, fb_result="BUILD_ERROR")
        print(f"  FB:   BUILD ERROR ({e})", flush=True)

# ── Summary: two distinct speedups + pass/fail ───────────────────────────────
def ok(v):
    return isinstance(v, (int, float)) and v >= 0

good = [t for t in TESTS if ok(rows[t]["nofb_fw_s"]) and ok(rows[t]["fb_link_s"])]
N = len(good)

sum_nofb_fw  = sum(rows[t]["nofb_fw_s"]  for t in good)
sum_nofb_run = sum(rows[t]["nofb_run_s"] for t in good)
sum_fb_link  = sum(rows[t]["fb_link_s"]  for t in good)
sum_fb_run   = sum(rows[t]["fb_run_s"]   for t in good)

# (a) "compile once": one-time SoC compile + N tests of fw-compile/link/run,
#     end to end — the realistic win for a whole sweep on a freshly built SoC.
nofb_total = nofb_soc_s + sum_nofb_fw + sum_nofb_run
fb_total   = fb_soc_s   + sum_fb_link + sum_fb_run
speedup_compile_once = nofb_total / fb_total if fb_total else float("nan")

# (b) "per-test compile & link" only — excludes the (amortizable) one-time SoC
#     build, isolating FB's incremental relink vs. noFB's full hex regeneration.
speedup_compile_link = sum_nofb_fw / sum_fb_link if sum_fb_link else float("nan")

print(f"\n{'='*70}\nSUMMARY over {N}/{len(TESTS)} tests   (CSV: {csv_path})\n{'='*70}")
print(f"  SoC compile      (once):   noFB {nofb_soc_s:9.1f}s   FB {fb_soc_s:9.1f}s")
print(f"  fw compile/link  (sum):    noFB {sum_nofb_fw:9.1f}s   FB {sum_fb_link:9.1f}s")
print(f"  run              (sum):    noFB {sum_nofb_run:9.1f}s   FB {sum_fb_run:9.1f}s")
print(f"  end-to-end total:          noFB {nofb_total:9.1f}s   FB {fb_total:9.1f}s")
print()
print(f"  Speedup — compile SoC once, amortized over {N} tests: {speedup_compile_once:6.2f}x")
print(f"  Speedup — per-test compile & link only:               {speedup_compile_link:6.2f}x")

print(f"\n  Pass/fail ({len(TESTS)} tests):")
for t in TESTS:
    r = rows[t]
    flag = "" if (r["nofb_result"] == "PASS" and r["fb_result"] == "PASS") else "  <-- needs attention"
    print(f"    {t:42s} noFB={r['nofb_result']:12s} FB={r['fb_result']:12s}{flag}")

print(f"\nSaved: {csv_path}")
