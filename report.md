# FireBridge Integration Analysis for Caliptra Tests

**Date**: 2026-05-20  
**Author**: Claude Code analysis  
**Repos**: `caliptra-docker` (ws/usr/caliptra-rtl v2.1.2), `axis-systolic-array/firebridge`

---

## 1. Architecture Overview

### 1.1 Caliptra RTL Architecture

```
External SoC Side                        caliptra_top DUT
─────────────────────────────────────────────────────────────
                         ┌───────────────────────────────────┐
SoC BFM ──s_axi_w/r_if──►│  soc_ifc (AXI slave)             │
(current: SV BFM)        │  ├─ Mailbox SRAM                  │
                         │  ├─ Fuse registers                 │
                         │  └─ Boot/reset control             │
                         │                AHB-lite (32-bit)  │
                         │  AHB MUX ◄─────────────── VeeR EL2│
AXI complex ◄──m_axi────►│  AXI DMA ──AHB──► SHA256           │
(current: SV SRAM)       │  controller       SHA512/3         │
                         │  (m_axi manager)  AES-GCM          │
                         │                   ECC secp384r1    │
                         │                   HMAC             │
                         │                   ML-DSA (adams-  │
                         │                   bridge)          │
                         │                   ML-KEM           │
                         │                   DOE, KV, PV, DV  │
                         └───────────────────────────────────┘
```

**External AXI interfaces on `caliptra_top`:**

| Port | Role | Width | Current driver |
|------|------|-------|----------------|
| `s_axi_w_if` / `s_axi_r_if` | AXI slave (SoC registers) | 32-bit data, 48-bit addr | `caliptra_top_tb_soc_bfm.sv` |
| `m_axi_w_if` / `m_axi_r_if` | AXI manager (DMA external memory) | 32-bit data, 48-bit addr | `caliptra_top_tb_axi_complex.sv` |

**Internal bus**: AHB-Lite 32-bit (17 slaves, VeeR EL2 as master). Not externally accessible — the crypto blocks (SHA256, AES, ECC, etc.) are all AHB slaves driven by VeeR from inside the DUT.

### 1.2 Current Testbench Flow

```
1. Compile RISC-V firmware (riscv64-unknown-elf-gcc → program.hex, dccm.hex, iccm.hex)
2. Build verilator sim (715 RTL files including VeeR EL2 + all crypto)
3. Run:
   └── SoC BFM drives s_axi: power-on → fuse load → boot trigger
       └── VeeR CPU starts: init_interrupts() → test firmware runs
           └── Firmware drives AHB → crypto blocks via AHB MUX
               └── Crypto completes (interrupt to VeeR) → firmware reads result
                   └── Firmware writes 0xff to STDOUT → TB detects pass/fail
```

### 1.3 FireBridge Current Capabilities

FireBridge (`fb_axi_vip.sv` + `fb_fw_wrap.h`) provides:

- **S side** (`S_COUNT` slave ports): C firmware calls `fb_write_reg(addr, val)` / `fb_read_reg(addr)` → DPI → SV `axi_write` / `axi_read` tasks → drives AXI bus as master toward a DUT AXI slave
- **M side** (`M_COUNT` master ports): Receives AXI manager traffic from DUT, serves it via `zipcpu_axi2ram` backed by a C byte-array (`fb_c_read_ddr8_addr32` / `fb_c_write_ddr8_addr32`)
- Congestion emulation via `VALID_PROB` / `READY_PROB`
- Supports Verilator, Vivado XSIM, Xcelium

**Current limitations (relevant to Caliptra):**

| Missing feature | Impact on Caliptra |
|-----------------|-------------------|
| AHB-Lite master | Cannot directly replace VeeR CPU (which drives AHB internally) |
| Interrupt forwarding (RTL→C) | All caliptra firmware uses `wfi`/ISR pattern for completion detection |
| AXI burst support on slave side (`awlen > 0`) | Mailbox multi-dword writes use bursts |
| AXI USER field on slave (`awuser`/`aruser`) | Caliptra uses USER for security filtering |

---

## 2. Two Integration Modes

There are two fundamentally different ways to plug FireBridge into Caliptra. The architecture determines the speedup.

### Mode A — External Interface Replacement (Zero Caliptra changes)

Replace only the external testbench components:
- FireBridge S_COUNT=1 → replaces `caliptra_top_tb_soc_bfm.sv` (drives `s_axi`)
- FireBridge M_COUNT=1 → replaces `caliptra_top_tb_axi_complex.sv` (serves `m_axi`)

**VeeR CPU still simulates inside caliptra_top.** C firmware implements the SoC boot sequence (fuse load, boot trigger, pass/fail detection) running natively.

**Speedup**: Negligible to ~1.5x. The SoC BFM is already simple SV tasks. VeeR simulation dominates.

**Benefit**: Enables parametric SoC test generation from C, cleaner test infrastructure, easier Python-driven stimulus. Not a simulation speed improvement.

### Mode B — Internal VeeR Replacement (Requires new FireBridge feature: AHB-Lite)

Add a `fb_ahb_vip.sv` module with AHB-Lite master capability. Modify `caliptra_top.sv` to conditionally bypass VeeR EL2 and expose the AHB bus to FireBridge:

```
Native C firmware
     │ DPI
     ▼
fb_ahb_vip ──AHB-Lite──► AHB MUX ──► SHA256, AES, ECC, ... (inside caliptra_top)
                 └─ also ──s_axi─► soc_ifc (boot sequence in C)
                 └─ M_COUNT ─► caliptra DMA memory
```

**VeeR CPU is bypassed.** The same C code that ran on VeeR now runs natively in the simulator process. AHB register access is DPI-driven. Interrupt completion is replaced by polling (or future interrupt forwarding).

**Speedup**: Major — see Section 4.

---

## 3. Easiest Tests to Integrate (Ranked)

The ranking is based on: firmware complexity, SoC BFM complexity, whether DMA is used, and whether the firmware can be trivially converted from interrupt-driven to polling.

### 3.1 For Mode A (current FireBridge, external interfaces only)

The "firmware" to port is the **SoC boot sequence** — not the caliptra firmware, which still runs on VeeR. The SoC BFM does: power-on, cptra_rst_b toggle, fuse writes via s_axi, boot trigger, monitor STDOUT.

All smoke tests are equivalent here. Simplest picks:

| Rank | Test | Why easiest | DMA needed? |
|------|------|-------------|-------------|
| 1 | `smoke_test_sha256` | Standard boot + wait for pass string; no DMA | No |
| 2 | `smoke_test_sha512` | Same pattern | No |
| 3 | `smoke_test_sha3` | Same pattern | No |
| 4 | `smoke_test_hmac` | Same pattern | No |
| 5 | `smoke_test_datavault_basic` | Same pattern | No |
| 6 | `smoke_test_dma_aes_gcm_short_1_dword` | Simplest DMA; need M_COUNT=1 | Yes (1 beat) |
| 7 | `smoke_test_dma` | Moderate DMA complexity | Yes |

### 3.2 For Mode B (with AHB-Lite FireBridge, replacing VeeR)

Here the "firmware" to port is the **actual test firmware** (sha256.c, etc.) from RISC-V to native C. The key concern is the interrupt pattern: all caliptra firmware calls `init_interrupts()` and uses `wfi` (wait-for-interrupt) via `wait_for_sha256_intr()` etc.

For FireBridge, we replace the interrupt wait with a polling loop on the status register — a trivial change.

**Criteria for "easiest":**
- Single accelerator (one AHB slave target)
- No DMA (no m_axi coordination)
- Simple register write → start → poll status → read result
- No key vault or security vault chaining

| Rank | Test | Firmware complexity | Ports needed | Notes |
|------|------|--------------------|----|-------|
| 1 | `smoke_test_sha256` | 16 reg writes + 1 ctrl + 8 reg reads | AHB only | Replace `wfi` with status poll; straightforward |
| 2 | `smoke_test_sha512` | Same pattern, 32 reg writes | AHB only | Identical structure to SHA256 |
| 3 | `smoke_test_sha3` / `smoke_test_cshake` | Similar register pattern | AHB only | KMAC/SHA3 same pattern |
| 4 | `smoke_test_aes_gcm` | Write key+IV+data, start, poll | AHB only | More registers but same flow |
| 5 | `smoke_test_datavault_basic` | Simple R/W of datavault regs | AHB only | No crypto wait loops |
| 6 | `smoke_test_dma_aes_gcm_short_1_dword` | DMA config + AES-GCM for 1 dword | AHB + m_axi | Smallest DMA test; good for first DMA validation |
| 7 | `rand_test_dma` | Complex randomized DMA | AHB + m_axi | Hard to port but highest payoff |

**Why NOT these tests for initial integration:**
- `smoke_test_mldsa`, `smoke_test_mlkem` — ML-DSA/ML-KEM firmware is complex (hundreds of reg interactions, progress registers). Port effort high, speedup minimal (HW dominates).
- `smoke_test_kv_*`, `smoke_test_ecc_*` — Key vault chaining across multiple AHB slaves; security state machine requirements.
- `fw_test_lms_*` — These are pre-compiled RUST/C binaries (no .c source to port). Source is in the ROM image.
- `smoke_test_mbox` — Mailbox protocol uses AXI bursts (awlen > 0 on s_axi), which FireBridge doesn't currently support.

---

## 4. Tests With Largest Simulation Speedup

The speedup from Mode B (VeeR bypass) is:

```
Speedup ≈ (VeeR CPU cycles per test) / (RTL-only cycles)
```

### 4.1 Speedup by Test Category

**Category 1: Pure CPU tests (largest relative speedup)**

These tests do little or no HW acceleration — almost all cycles are VeeR instruction execution.

| Test | What VeeR does | VeeR cycles est. | HW cycles est. | Speedup |
|------|----------------|-----------------|----------------|---------|
| `hello_world_iccm` | Copy code to ICCM, run printf | ~50K | ~0 | ∞ |
| `iccm_lock` | Write ICCM lock registers | ~15K | ~0 | ~∞ |
| `memCpy_ROM_to_dccm` | Copy memory blocks | ~30K | ~0 | ~∞ |
| `infinite_loop` | CPU loop + JTAG check | ~∞ | ~0 | N/A |

**Category 2: Simple crypto smoke tests (large speedup)**

Boot overhead (~5K-10K VeeR cycles) + register programming + interrupt setup + result verification. The HW operation itself takes few hundred cycles.

| Test | VeeR cycles est. | HW cycles est. | Speedup est. |
|------|-----------------|----------------|-------------|
| `smoke_test_sha256` | ~12K (boot+ISR+FW) | ~500 (64 rounds) | **~20-25x** |
| `smoke_test_sha512` | ~13K | ~800 | **~15-20x** |
| `smoke_test_sha3` | ~12K | ~600 | **~20x** |
| `smoke_test_cshake` | ~13K | ~600 | **~20x** |
| `smoke_test_hmac` | ~15K | ~2K | **~7-10x** |
| `smoke_test_aes_gcm` | ~15K | ~2K | **~7-10x** |
| `smoke_test_datavault_basic` | ~8K | ~100 | **~30-50x** |
| `smoke_test_pcr_signing` | ~12K | ~300 | **~25x** |

**Category 3: DMA tests (large absolute speedup)**

VeeR generates/verifies data, configures DMA. The DMA transfers happen in RTL cycles but the setup and verification dominate.

| Test | VeeR cycles est. | RTL-only cycles | Speedup est. |
|------|-----------------|----------------|-------------|
| `smoke_test_dma_aes_gcm_short_1_dword` | ~20K | ~5K | **~4x** |
| `smoke_test_dma` | ~80K | ~30K | **~3-5x** |
| `smoke_test_dma_aes_gcm_long` | ~200K+ | ~50K | **~5-10x** |
| `rand_test_dma` | ~800K (randomization) | ~100K | **~10-20x** |

**Category 4: Randomized crypto tests (moderate-high speedup)**

The "randomized" tests run many iterations or randomized inputs, multiplying VeeR overhead.

| Test | Notes | Speedup est. |
|------|-------|-------------|
| `smoke_test_sha256_wntz_rand` | Multiple SHA256 with randomized WNTZ parameters | **~15-25x** |
| `randomized_pcr_ecc_signing` | ECC signing with random keys | **~5-10x** |
| `randomized_mldsa_invalid_verify` | Multiple ML-DSA verifications | **~1.1-1.5x** (HW-bound) |

**Category 5: Post-quantum (minimal speedup)**

The hardware accelerator (adams-bridge) takes millions of cycles. VeeR's setup overhead is tiny relative to HW time.

| Test | VeeR cycles est. | HW cycles est. | Speedup est. |
|------|-----------------|----------------|-------------|
| `smoke_test_mldsa` | ~100K | ~10M | **~1.01x** |
| `smoke_test_mlkem` | ~80K | ~8M | **~1.01x** |
| `smoke_test_ecc_keygen` | ~40K | ~5M | **~1.008x** |

**Category 6: LMS firmware tests (exceptional speedup)**

`fw_test_lms_*` (32 variants) implement the Leighton-Micali Signature scheme **entirely in software** — there is no LMS hardware accelerator in Caliptra. The VeeR CPU executes the full LMS algorithm (hash chains, tree traversal). These are pre-compiled RUST/C binaries (`fw_test_lms24/fw_test_lms24`).

| Test | VeeR cycles est. | HW cycles | Speedup est. |
|------|-----------------|-----------|-------------|
| `fw_test_lms24` (h=5) | ~50M | ~0 | **~500-5000x** |
| `fw_test_lms24` (h=10) | ~200M | ~0 | **~1000-10000x** |
| `fw_test_lms_n32_w1_h20` | ~2B+ | ~0 | **Hours→seconds** |

These are the most transformative candidates. Currently these tests likely take 10-60 minutes each on Verilator. With FireBridge, they'd run in seconds.

### 4.2 Speedup Summary — Top Candidates

| Rank | Test(s) | Speedup | Reason |
|------|---------|---------|--------|
| 1 | `fw_test_lms_*` (32 variants) | **500-10,000x** | Pure SW LMS, no HW accel |
| 2 | `hello_world_iccm`, `iccm_lock`, memory copy tests | **100x+** | Pure CPU, zero HW |
| 3 | `rand_test_dma` | **10-20x** | FW randomization overhead eliminated |
| 4 | `smoke_test_datavault_basic`, `smoke_test_pcr_*` | **25-50x** | Fast HW, large boot overhead |
| 5 | `smoke_test_sha256/512/3`, `smoke_test_cshake` | **15-25x** | Fast HW, decent FW overhead |
| 6 | `smoke_test_dma_*` | **4-10x** | DMA transfer is HW-bound |
| 7 | `smoke_test_mldsa`, `smoke_test_mlkem` | **~1%** | HW completely dominates |

---

## 5. FireBridge Feature Roadmap

### Feature Priority Matrix

| Priority | Feature | Tests unlocked | Effort |
|----------|---------|----------------|--------|
| **P0** | AHB-Lite master (`fb_ahb_vip.sv`) | ALL Mode B tests | 2-3 weeks |
| **P1** | Interrupt forwarding (RTL→C flags) | All interrupt-driven tests (no firmware rewrite) | 1 week |
| **P2** | AXI burst support on slave (`awlen > 0`) | Mailbox tests, large transfers | 1 week |
| **P3** | AXI USER field passthrough | Security state / strap tests | 3 days |
| **P4** | Multiple AHB master ports (LSU + system bus) | Precise pipeline timing tests | 2 weeks |

### Phase 1 — AHB-Lite Master (P0, unlocks all Mode B)

**New file**: `firebridge/fb_ahb_vip.sv`

AHB-Lite is simpler than AXI (no IDs, no out-of-order, pipelined address/data):

```systemverilog
module fb_ahb_vip #(
  parameter ADDR_W  = 32,
  parameter DATA_W  = 32,
  S_COUNT           = 1,   // number of address windows
  S_AHB_BASE_ADDR   = {32'h7000_0000}
)(
  input  bit clk, rstn,
  output bit firebridge_done,
  // AHB-Lite master port (drives caliptra AHB MUX)
  output bit [ADDR_W-1:0]  haddr,
  output bit [1:0]         htrans,
  output bit               hwrite,
  output bit [2:0]         hsize,
  output bit [2:0]         hburst,
  output bit [DATA_W-1:0]  hwdata,
  input  bit [DATA_W-1:0]  hrdata,
  input  bit               hready,
  input  bit               hresp
);
```

DPI tasks (mirroring existing `fb_task_write_reg` / `fb_task_read_reg`):
```c
// In fb_fw_wrap.h — AHB variant
static inline void fb_ahb_write(fb_reg_t *addr, fb_reg_t data) {
  fb_task_ahb_write_reg((u64)(uintptr_t)addr, (u64)data);
}
static inline fb_reg_t fb_ahb_read(fb_reg_t *addr) {
  fb_task_ahb_read_reg((u64)(uintptr_t)addr);
  return (fb_reg_t)fb_fn_ahb_read_reg();
}
```

**Caliptra modification** (`caliptra_top.sv` or new `caliptra_top_fb_tb.sv`):

```systemverilog
`ifdef FIREBRIDGE
  // Replace VeeR with FireBridge AHB master
  fb_ahb_vip #(
    .ADDR_W(32), .DATA_W(32)
  ) cpu_fb (
    .clk   (core_clk),
    .rstn  (cptra_rst_b),
    .haddr (initiator_inst.haddr),  // connect to AHB MUX initiator port
    .hwrite(initiator_inst.hwrite),
    .hwdata(initiator_inst.hwdata),
    .hrdata(initiator_inst.hrdata),
    ...
    .firebridge_done(firebridge_done)
  );
`else
  // Normal VeeR path (existing)
  el2_veer_wrapper rvtop (.haddr(initiator_inst.haddr), ...);
`endif
```

The firmware C code (`smoke_test_sha256.c`) needs one change: replace `wait_for_sha256_intr()` with a status register poll:

```c
// Before (interrupt-driven, VeeR):
sha256_gen_hash(block, digest, SHA256_MODE_SHA_256);
// (internally uses wfi + ISR)

// After (polling, FireBridge):
fb_ahb_write(sha256_ctrl, SHA256_CTRL_INIT_MASK);
while (!(fb_ahb_read(sha256_status) & SHA256_STATUS_VALID_MASK));
for (int i = 0; i < 8; i++) result[i] = fb_ahb_read(sha256_digest + i*4);
```

This is the only required change per test — all register addresses are already defined in `caliptra_defines.h`.

### Phase 2 — Interrupt Forwarding (P1, eliminates firmware rewrites)

Rather than converting all firmware from interrupt-driven to polling, add a mechanism to forward RTL interrupts to C firmware. This lets the existing firmware code run unmodified (except replacing raw pointer writes with `fb_ahb_write`).

**Mechanism**: `fb_irq_flags[]` array in shared memory, set by a SV always block, polled by a C wrapper around `wfi`:

```systemverilog
// In fb_ahb_vip.sv - add interrupt input
input bit [31:0] irq_in,
import "DPI-C" function void fb_c_set_irq(int unsigned irq_num);
always @(posedge clk) begin
  for (int i = 0; i < 32; i++)
    if (irq_in[i]) fb_c_set_irq(i);
end
```

```c
// In fb_fw_wrap.h
extern volatile uint32_t fb_irq_flags[32];  // set by fb_c_set_irq DPI
#define wfi()  do { while (!fb_any_irq_pending()) {} } while(0)
```

Connect `irq_in` to caliptra's 26-interrupt vector. Firmware retains its `init_interrupts()` + ISR pattern, just replacing `wfi` with the FB polling equivalent — a pure preprocessor define.

### Phase 3 — AXI Burst on Slave (P2, enables mailbox tests)

Extend `fb_axi_vip.sv`'s `axi_write` task to support `awlen > 0`:

```systemverilog
task axi_burst_write(input [ADDR_W-1:0] base_addr,
                     input [DATA_W-1:0] data[], 
                     input int          num_beats);
  // awlen = num_beats-1
  // Loop: issue wdata beats until wlast
endtask
```

Add to `fb_fw_wrap.h`:
```c
void fb_burst_write(fb_reg_t *base, fb_reg_t *data, int count);
```

This enables the mailbox protocol (send FW commands, multi-dword payloads) and large-block SHA512 tests with pre-loaded data arrays.

### Phase 4 — AXI USER Field (P3, enables security tests)

Caliptra uses `awuser`/`aruser` to identify AXI transactions (e.g., caliptra DMA AXI user filtering). Add:

```systemverilog
parameter S_AXI_USER_WIDTH = 32,
parameter S_AXI_USER_VALUE = 32'h0,  // configurable per slave
...
s_axi_awuser[i] <= S_AXI_USER_WIDTH'(S_AXI_USER_VALUE);
```

---

## 6. Recommended Integration Plan

### Step 1 — Validate Mode A now (0 FireBridge changes)

**Goal**: Prove the concept, set up test infrastructure.

- Create `caliptra_fb_top_tb.sv` that instantiates `caliptra_top` + `fb_axi_vip` (S_COUNT=1, M_COUNT=0)
- Port the SoC BFM boot sequence to C: power-on → s_axi fuse writes → boot trigger → poll for pass/fail on a mapped status register
- Target test: `smoke_test_sha256` (VeeR still runs internally, SHA256 works normally)
- Measure baseline simulation time vs original BFM

**Expected outcome**: Same test correctness, same speed, but clean FireBridge-driven testbench. Validates the s_axi parameter mapping.

### Step 2 — Build `fb_ahb_vip.sv` and run `smoke_test_sha256` in Mode B

**Goal**: First test with VeeR completely bypassed.

- Implement `fb_ahb_vip.sv` (AHB-Lite single-master, DPI tasks for read/write)
- Create `caliptra_top_firebridge_tb.sv` with `FIREBRIDGE` define, VeeR bypassed
- Port `smoke_test_sha256.c` to polling mode (replace `wait_for_sha256_intr` with status register poll)
- Run both versions and measure speedup

**Expected speedup**: ~20-25x over Verilator baseline.

### Step 3 — Expand to `smoke_test_sha512`, `sha3`, `aes_gcm`, `hmac`

- These are identical structural changes to Step 2
- Each test requires only the firmware polling conversion
- Validate FireBridge memory model parameters (data width, address width) match caliptra's AHB params
- Build a regression suite of ~10 crypto smoke tests

**Estimated effort**: 1 week after Step 2.

### Step 4 — Add interrupt forwarding and run `smoke_test_sha3_interrupt`

**Goal**: Eliminate firmware rewrites for interrupt-driven tests.

- Implement `fb_irq_flags[]` + `fb_c_set_irq()` mechanism
- Connect caliptra's 26-vector interrupt bus to `fb_ahb_vip.irq_in`
- Run `smoke_test_sha3_interrupt` without any firmware changes (beyond raw pointer → `fb_ahb_write`)
- Expand to kv_*, hmac_kv_*, pcr_* tests

**Expected outcome**: Full interrupt-driven test suite portable to FireBridge without per-test polling conversions.

### Step 5 — Port `rand_test_dma` with M_COUNT=1

**Goal**: Biggest absolute speedup for a structured test.

- Add `fb_axi_vip` M_COUNT=1 to provide DMA memory via `zipcpu_axi2ram`
- Port `rand_test_dma.c` (remove VeeR-specific `soc_ifc_axi_dma_*` wrappers, call AHB DMA config registers directly)
- FireBridge byte memory stores randomized payload; DMA reads/writes it
- AXI data width must match caliptra's DMA width (32-bit)

**Expected speedup**: ~10-20x.

### Step 6 — `fw_test_lms_*` (the biggest win)

**Goal**: Convert the highest-value tests (SW LMS).

- `fw_test_lms_*` are pre-compiled binaries — requires obtaining source or disassembling
- The LMS firmware is pure software: if source is available, `fb_ahb_write`/`fb_ahb_read` replacements suffice
- If source is unavailable: run LMS natively without RTL at all (LMS doesn't use HW), just validate the pure SW path
- Estimated speedup: **500-10,000x** depending on tree height

**Expected outcome**: Tests that currently take 10-60 minutes run in seconds.

---

## 7. Summary Tables

### Easiest Tests to Integrate (current FireBridge capabilities sufficient for Mode A)

| Test | Mode A effort | Mode B effort (with AHB) | Why first |
|------|--------------|--------------------------|-----------|
| `smoke_test_sha256` | Low | Low (polling conversion) | Gold standard; simplest crypto flow |
| `smoke_test_sha512` | Low | Low | Identical structure |
| `smoke_test_sha3` | Low | Low | Same |
| `smoke_test_datavault_basic` | Low | Low | No wait loops, pure R/W |
| `smoke_test_dma_aes_gcm_short_1_dword` | Medium | Medium | Smallest DMA; validates M side |

### Biggest Speedup Tests (with AHB-Lite FireBridge)

| Test | Speedup estimate | Blocker |
|------|-----------------|---------|
| `fw_test_lms_*` (32 variants) | 500-10,000x | Source availability (pre-compiled bins) |
| `hello_world_iccm` | >100x | Minor (assembly, needs C equivalent) |
| `smoke_test_datavault_basic/mini` | 30-50x | None after AHB support |
| `smoke_test_sha256/512/3` | 15-25x | Polling conversion (trivial) |
| `rand_test_dma` | 10-20x | DMA setup + M_COUNT=1 needed |
| `smoke_test_dma_aes_gcm_long` | 5-10x | Same as above |
| `smoke_test_mldsa` | ~1% | HW-bound; not worth porting |

### Required FireBridge Features by Phase

| Phase | Feature | New file | Caliptra change |
|-------|---------|----------|----------------|
| Now | Mode A validation | — | New `caliptra_fb_top_tb.sv` |
| 1 | AHB-Lite master | `fb_ahb_vip.sv` | `ifdef FIREBRIDGE` bypass in TB |
| 2 | Interrupt forwarding | Update `fb_ahb_vip.sv` + `fb_fw_wrap.h` | Connect irq bus |
| 3 | AXI burst (slave) | Update `fb_axi_vip.sv` + `fb_fw_wrap.h` | None |
| 4 | AXI USER field | Update `fb_axi_vip.sv` | Set user value |

---

## 8. Key Architectural Decision

The single most impactful change is **`fb_ahb_vip.sv` — AHB-Lite master support**.

All caliptra crypto blocks (SHA256, SHA512, SHA3, AES, HMAC, ECC, KV, PV, DV) are AHB-Lite slaves. The VeeR EL2 CPU is their only master. FireBridge needs to become that master.

AHB-Lite is significantly simpler to implement than AXI (no IDs, no out-of-order, sequential transactions only). The protocol is:

```
Cycle 1 (address phase): HADDR + HTRANS=NONSEQ + HWRITE + HSIZE valid
Cycle 2+ (data phase):   HWDATA valid (write), HRDATA valid (read), wait HREADY
```

This maps directly to the existing `axi_write`/`axi_read` task pattern in `fb_axi_vip.sv`, just simplified. Implementation complexity is ~150-200 lines of SystemVerilog.

Once this exists, a complete AHB-based FireBridge integration for Caliptra becomes a new testbench file (~100 lines) plus per-test firmware porting (5-20 lines of `wait_for_*_intr` → polling substitutions).
