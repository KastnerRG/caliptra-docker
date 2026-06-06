#!/usr/bin/env python3
"""
FireBridge AHB speedup plot.

Collects all speedup_ahb_*.csv files, keeps the latest measurement per test,
writes a merged CSV, and produces a stacked-bar + speedup-line chart.

Usage:
    python3 plot_speedup.py [--out-dir DIR]

Outputs (in OUT_DIR, default: experiments/):
    merged_speedup_TIMESTAMP.csv
    speedup_plot_TIMESTAMP.pdf
"""

import argparse
import csv
import sys
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.ticker import AutoMinorLocator
import numpy as np

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
RUNS_DIR   = SCRIPT_DIR.parent / "runs"

# ─── Tier groups (display order; tests without data are silently skipped) ─────
TIER_GROUPS = [
    # ("T0 – Basic Crypto", [
    #     "smoke_test_sha256",
    #     "smoke_test_sha512",
    #     "smoke_test_hmac",
    # ]),
    ("Crypto Variants", [
        "smoke_test_sha512_restore",
        "smoke_test_sha256_wntz",
        "smoke_test_sha256_wntz_rand",
        "smoke_test_sha3_regs",
        "smoke_test_zeroize_crypto",
        "smoke_test_hmac_errortrigger",
    ]),
    ("SHA3 / DataVault / PCR", [
        "smoke_test_sha3",
        "smoke_test_cshake",
        "smoke_test_sha3_externalmu",
        "smoke_test_sha3_interrupt",
        "pv_hash_zeroize",
        "smoke_test_datavault_basic",
        "smoke_test_datavault_mini",
        "smoke_test_datavault_lock",
        "smoke_test_datavault_reset",
        "smoke_test_pcr_signing",
        "smoke_test_pcr_zeroize",
    ]),
    ("KeyVault / ECC / DOE", [
        "smoke_test_doe_rand",
        "smoke_test_doe_cg",
        "smoke_test_doe_scan",
        "smoke_test_doe_kv_ocp_progress",
        "smoke_test_hek_flow",
        "smoke_test_kv_lock_use_mid_read",
        "kv_entry_read_err",
        "smoke_test_kv_hmac_flow",
        "smoke_test_fw_kv_backtoback_hmac",
        "smoke_test_hmac_kv_ocp_progress",
        "smoke_test_kv_hmac_multiblock_flow",
        "smoke_test_kv_doe",
        "smoke_test_kv_securitystate",
        "smoke_test_kv_uds_reset",
        "smoke_test_kv_cg",
        "smoke_test_kv_write_scan_mode",
        "smoke_test_kv_rules_ocp_lock",
        "smoke_test_kv_swwe_lock",
        "smoke_test_kv_ecc_flow1",
        "smoke_test_kv_ecc_flow2",
        "smoke_test_ecc_flow1_kv_ocp_progress",
        "smoke_test_ecc_flow2_kv_ocp_progress",
        "smoke_test_kv_mldsa",
        "smoke_test_kv_parallel_access",
        "smoke_test_ecc_keygen",
        "smoke_test_ecc_sign",
        "smoke_test_ecc_verify",
        "smoke_test_ecdh",
        "smoke_test_ecc_errortrigger2",
        "smoke_test_ecc_errortrigger3",
        "smoke_test_ecc_errortrigger4",
        "smoke_test_ecc_errortrigger5",
        "randomized_pcr_ecc_signing",
        "smoke_test_kv_crypto_flow",
    ]),
    ("Peripheral / Misc", [
        "smoke_test_strap",
        "smoke_test_hw_config",
        "smoke_test_wdt",
        "smoke_test_wdt_rst",
        "smoke_test_trng",
        "smoke_test_qspi",
        "smoke_test_uart",
    ]),
    # ("AXI DMA", [
    #     "smoke_test_dma",
    #     "smoke_test_dma_aes_gcm",
    #     "smoke_test_dma_aes_gcm_short_1_dword",
    #     "smoke_test_dma_aes_gcm_short_dword",
    #     "smoke_test_dma_aes_gcm_cmd_err",
    #     "smoke_test_dma_aes_gcm_collision_test",
    #     "smoke_test_dma_aes_gcm_rd_enc_axi_err",
    #     "smoke_test_dma_aes_gcm_wr_enc_axi_err",
    #     "smoke_test_dma_aes_gcm_non_gcm_en_dec",
    #     "smoke_test_dma_aes_kv",
    # ]),
    # ("T6 – Mailbox", [
    #     "smoke_test_mbox",
    #     "smoke_test_mbox_cg",
    #     "smoke_test_mbox_byte_read",
    # ]),
    ("ML-DSA / ML-KEM", [
        "smoke_test_mldsa",
        "smoke_test_mldsa_kat",
        "smoke_test_mldsa_keygen_sign_vfy_rand",
        "smoke_test_mldsa_keygen_standalone_sign_vfy_rand",
        "smoke_test_mldsa_errortrigger",
        "smoke_test_mldsa_sign_rnd",
        "smoke_test_mldsa_edge",
        "smoke_test_mldsa_externalmu",
        "smoke_test_mldsa_externalmu_keygen_sign_vfy_rand",
        "smoke_test_mldsa_zeroize",
        "smoke_test_mldsa_locked_api",
        "mldsa_pcr_inject_failure",
        "randomized_mldsa_invalid_verify",
        "randomized_pcr_mldsa_signing",
        "smoke_test_mldsa_kv_ocp_progress",
        "smoke_test_mlkem",
        "smoke_test_mlkem_errortrigger",
        "smoke_test_mlkem_shared_key",
        "smoke_test_mlkem_kv",
        "smoke_test_mlkem_kv_ocp_progress",
        "smoke_test_mlkem_all_zero_seed",
        "smoke_test_mlkem_locked_api",
    ]),
]

# ─── Plot knobs ───────────────────────────────────────────────────────────────
TITLE           = ""
BAR_SEP         = 1     # horizontal gap between FB and VeeR bars within one test
TEST_SEP        = 1     # horizontal distance between adjacent tests (1.0 = bars touch)
GROUP_GAP       = 1     # extra horizontal space inserted between test groups
GROUP_LABEL_Y   = -0.28 # vertical position of group name in axes-fraction coords
                         # (0 = axis bottom, negative = below; more negative = further down)
FONT_SIZE       = 20     # base font size; tick labels = 0.8×, group labels = 0.9×,
                         # axis labels = 1.4×, legend = 1.0×, title = 1.3×

# ─── Colors ───────────────────────────────────────────────────────────────────
C_FB_COMPILE   = "#1b4f8a"  # dark blue
C_FB_RUN       = "#74b9e0"  # light blue
C_NOFB_COMPILE = "#8b1a1a"  # dark red
C_NOFB_RUN     = "#e08060"  # salmon
C_SPD_TOTAL    = "#2ca02c"  # green
C_SPD_RUN      = "#ff7f0e"  # orange
C_SPD_COMPILE  = "#9467bd"  # purple


# ─── Data loading ─────────────────────────────────────────────────────────────
_VALID_PREFIXES = (
    "smoke_test_", "pv_", "kv_", "randomized_", "mldsa_", "mlkem_",
    "fw_test_", "rand_test_",
)

def _valid_name(name: str) -> bool:
    """Reject corrupted test names (CSV-splice artifacts, truncations, etc.)"""
    if not name or len(name) > 80:
        return False
    if not all(c.isalnum() or c in "_-." for c in name):
        return False
    return any(name.startswith(p) for p in _VALID_PREFIXES)


def load_latest(runs_dir: Path) -> dict:
    """Read all CSVs, return {test: row_dict} keeping the row from the newest file."""
    csvs = sorted(runs_dir.glob("speedup_ahb_*.csv"))  # lexicographic = chronological
    data: dict[str, tuple[str, dict]] = {}  # test -> (timestamp, row)
    for path in csvs:
        ts = path.stem.removeprefix("speedup_ahb_")
        try:
            with open(path, newline="") as f:
                for row in csv.DictReader(f):
                    test = row.get("test", "").strip()
                    if not test or not _valid_name(test):
                        continue
                    if test not in data or ts > data[test][0]:
                        try:
                            d = {k: float(row[k]) for k in
                                 ("fb_compile_s", "fb_run_s",
                                  "nofb_compile_s", "nofb_run_s")}
                            data[test] = (ts, d)
                        except (KeyError, ValueError):
                            pass
        except OSError as e:
            print(f"  warning: {path.name}: {e}", file=sys.stderr)
    return {t: v[1] for t, v in data.items()}


# ─── Test name shortening ─────────────────────────────────────────────────────
def shorten(name: str, maxlen: int = 30) -> str:
    s = name.removeprefix("smoke_test_")
    s = s.replace("randomized_", "rnd_")
    s = s.replace("errortrigger", "errtrig")
    s = s.replace("externalmu", "extmu")
    s = s.replace("keygen_sign_vfy_rand", "kg_sgn_vfy_rnd")
    s = s.replace("keygen_standalone_sign_vfy_rand", "kg_sa_sgn_vfy_rnd")
    s = s.replace("ocp_progress", "ocp")
    if len(s) > maxlen:
        s = s[:maxlen - 1] + "…"
    return s


# ─── Group ordering ───────────────────────────────────────────────────────────
def ordered_groups(data: dict, min_run_speedup: float = 0.0) -> list:
    """Return [(label, [test, ...]), ...] with only tests that have data
    and meet the minimum run speedup threshold."""
    def passes(t):
        d = data[t]
        if d["fb_run_s"] <= 0:
            return False
        return (d["nofb_run_s"] / d["fb_run_s"]) >= min_run_speedup

    seen: set[str] = set()
    groups = []
    for label, tests in TIER_GROUPS:
        have = [t for t in tests if t in data and passes(t)]
        if have:
            groups.append((label, have))
            seen.update(have)
    other = [t for t in sorted(data) if t not in seen and passes(t)]
    if other:
        groups.append(("Other", other))
    return groups


# ─── Merged CSV ───────────────────────────────────────────────────────────────
def save_merged_csv(data: dict, groups: list, out_path: Path) -> None:
    fields = ["tier", "test",
              "fb_compile_s", "fb_run_s", "nofb_compile_s", "nofb_run_s",
              "speedup_run", "speedup_compile", "speedup_total"]
    with open(out_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for tier, tests in groups:
            for test in tests:
                d = data[test]
                fb_tot   = d["fb_compile_s"]   + d["fb_run_s"]
                nofb_tot = d["nofb_compile_s"] + d["nofb_run_s"]
                w.writerow({
                    "tier":            tier,
                    "test":            test,
                    "fb_compile_s":    d["fb_compile_s"],
                    "fb_run_s":        d["fb_run_s"],
                    "nofb_compile_s":  d["nofb_compile_s"],
                    "nofb_run_s":      d["nofb_run_s"],
                    "speedup_run":     round(d["nofb_run_s"] / d["fb_run_s"], 3)
                                       if d["fb_run_s"] > 0 else "",
                    "speedup_compile": round(d["nofb_compile_s"] / d["fb_compile_s"], 3)
                                       if d["fb_compile_s"] > 0 else "",
                    "speedup_total":   round(nofb_tot / fb_tot, 3)
                                       if fb_tot > 0 else "",
                })


# ─── Plot ─────────────────────────────────────────────────────────────────────
def make_plot(data: dict, groups: list, out_path: Path,
              min_run_speedup: float = 0.0) -> None:
    # ── X-position layout ─────────────────────────────────────────────────────
    # Each test occupies 1 unit. Groups separated by an extra GROUP_GAP units.
    BAR_W = 0.36   # width of each bar
    # BAR_SEP, GROUP_GAP, GROUP_LABEL_Y come from the top-of-file knobs

    x_of: dict[str, float] = {}   # test -> center x
    span_of: list[tuple]   = []   # (x_lo, x_hi, label) per group
    x = 0.0
    half = TEST_SEP / 2
    for label, tests in groups:
        lo = x - half
        for test in tests:
            x_of[test] = x
            x += TEST_SEP
        span_of.append((lo, x - half, label))
        x += GROUP_GAP
    x_max = x - GROUP_GAP

    n = len(x_of)
    fig_w = max(22, n * 0.58 + 4)
    fig_h = fig_w * 6 / 16
    fig, ax1 = plt.subplots(figsize=(fig_w, fig_h))
    ax2 = ax1.twinx()

    # ── Bars (run time only) ──────────────────────────────────────────────────
    xs_mid, spd_run = [], []

    for _, tests in groups:
        for test in tests:
            xc = x_of[test]
            d  = data[test]
            xfb   = xc - BAR_W / 2 - BAR_SEP / 2
            xnofb = xc + BAR_W / 2 + BAR_SEP / 2

            ax1.bar(xfb,   d["fb_run_s"],   BAR_W, color=C_FB_RUN,   zorder=3)
            ax1.bar(xnofb, d["nofb_run_s"], BAR_W, color=C_NOFB_RUN, zorder=3)

            xs_mid.append(xc)
            spd_run.append(d["nofb_run_s"] / d["fb_run_s"]
                           if d["fb_run_s"] > 0 else np.nan)

    # ── Speedup line (right y-axis) ───────────────────────────────────────────
    ax2.plot(xs_mid, spd_run, "o-", color=C_SPD_TOTAL, lw=1.6, ms=4.5,
             label="Speedup (run)", zorder=5)
    ax2.axhline(1.0, color="#888888", lw=0.8, ls="--", alpha=0.6, zorder=2)

    # ── Group separator lines ─────────────────────────────────────────────────
    for i, (lo, hi, _) in enumerate(span_of):
        if i > 0:
            ax1.axvline(lo, color="#bbbbbb", lw=0.9, ls="--", zorder=1)

    # ── Alternating group backgrounds ─────────────────────────────────────────
    for i, (lo, hi, _) in enumerate(span_of):
        if i % 2 == 0:
            ax1.axvspan(lo, hi, color="#f5f5f5", alpha=0.5, zorder=0)

    # ── X tick labels (test names, 90°) ───────────────────────────────────────
    all_tests = [t for _, tests in groups for t in tests]
    ax1.set_xticks([x_of[t] for t in all_tests])
    ax1.set_xticklabels([shorten(t) for t in all_tests],
                        rotation=90, ha="center", va="top", fontsize=FONT_SIZE * 0.8)
    ax1.tick_params(axis="x", length=4, pad=2)

    # ── Group labels below tick labels ────────────────────────────────────────
    trans = ax1.get_xaxis_transform()
    for lo, hi, label in span_of:
        cx = (lo + hi) / 2.0
        ax1.plot([lo + 0.3, hi - 0.3], [GROUP_LABEL_Y + 0.02, GROUP_LABEL_Y + 0.02],
                 transform=trans, color="#999999", lw=0.9, clip_on=False,
                 solid_capstyle="butt")
        for bx in [lo + 0.3, hi - 0.3]:
            ax1.plot([bx, bx], [GROUP_LABEL_Y + 0.05, GROUP_LABEL_Y + 0.02],
                     transform=trans, color="#999999", lw=0.9, clip_on=False)
        ax1.text(cx, GROUP_LABEL_Y, label, transform=trans,
                 ha="center", va="top", fontsize=FONT_SIZE * 0.9, fontweight="bold",
                 color="#333333", clip_on=False)

    # ── Axes formatting ───────────────────────────────────────────────────────
    ax1.set_xlim(-half - 0.2, x_max + half + 0.2)
    ax1.set_ylim(bottom=0)
    ax2.set_ylim(bottom=0)

    ax1.set_ylabel("Wall-clock time (s)", fontsize=FONT_SIZE * 1.4)
    ax2.set_ylabel("Speedup  (noFB / FB)", fontsize=FONT_SIZE * 1.4)
    ax2.tick_params(axis="y", labelcolor="#333333")

    ax1.set_axisbelow(True)
    ax1.yaxis.grid(True, which="major", color="#dddddd", lw=0.7, zorder=0)
    ax1.yaxis.grid(True, which="minor", color="#eeeeee", lw=0.35, zorder=0)
    ax1.yaxis.set_minor_locator(AutoMinorLocator())

    # ── Legends ───────────────────────────────────────────────────────────────
    bar_handles = [
        mpatches.Patch(color=C_FB_RUN,   label="FireBridge run"),
        mpatches.Patch(color=C_NOFB_RUN, label="VeeR run"),
    ]
    leg1 = ax1.legend(handles=bar_handles, loc="upper left",
                      fontsize=FONT_SIZE, framealpha=0.88, ncol=2, borderpad=0.6)
    ax1.add_artist(leg1)

    spd_h, spd_l = ax2.get_legend_handles_labels()
    ax2.legend(spd_h, spd_l, loc="upper right", fontsize=FONT_SIZE, framealpha=0.88)

    # ── Title ─────────────────────────────────────────────────────────────────
    ts_label = datetime.now().strftime("%Y-%m-%d")
    filter_note = (f"  ·  run speedup ≥ {min_run_speedup:.0f}×"
                   if min_run_speedup > 0 else "")
    # ax1.set_title(
    #     f"{TITLE}  ·  {n} tests{filter_note}  ·  {ts_label}\n"
    #     "Bars: run time · Line: speedup = VeeR run / FB run",
    #     fontsize=FONT_SIZE * 1.3, pad=7)

    plt.tight_layout()
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot: {out_path}")


# ─── Main ─────────────────────────────────────────────────────────────────────
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=str(SCRIPT_DIR.parent),
                    help="Directory for output files (default: experiments/)")
    ap.add_argument("--min-run-speedup", type=float, default=0.0,
                    help="Exclude tests with run speedup below this threshold")
    args = ap.parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Load
    data = load_latest(RUNS_DIR)
    if not data:
        sys.exit(f"No CSV data found in {RUNS_DIR}")
    print(f"Loaded {len(data)} unique tests from {len(list(RUNS_DIR.glob('speedup_ahb_*.csv')))} CSVs")

    # Order
    groups = ordered_groups(data, min_run_speedup=args.min_run_speedup)
    n_plot = sum(len(g[1]) for g in groups)
    print(f"Plotting {n_plot} tests across {len(groups)} groups:")
    for label, tests in groups:
        print(f"  {label}: {len(tests)} tests")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Merged CSV
    csv_path = out_dir / f"merged_speedup.csv"
    save_merged_csv(data, groups, csv_path)
    print(f"CSV:  {csv_path}")

    # Plot
    suffix = f"_min{args.min_run_speedup:.0f}x" if args.min_run_speedup > 0 else ""
    png_path = out_dir / f"speedup_plot.png"
    make_plot(data, groups, png_path, min_run_speedup=args.min_run_speedup)


if __name__ == "__main__":
    main()
