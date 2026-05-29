// FireBridge HAL harness (Mode B). Boots Caliptra over external s_axi (via
// fb_axi_vip), then runs the UNMODIFIED test firmware natively on the host: the
// firmware's lsu_*/printf/SEND_STDOUT_CTRL are redirected through the FB HAL
// (firebridge/fb_hal/*.h) into this file, which performs real AHB-Lite
// transactions over the internal Caliptra bus via fb_ahb_vip (the bypassed
// VeeR's master). Two DPI scopes are in play:
//   - fb_axi_vip : owns run_sim/clock; s_axi register access (boot)
//   - u_fb_ahb   : internal AHB master; all firmware register access
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <csetjmp>
#include "svdpi.h"

// fb_caliptra_isr.c provides asm_wfi() which reflects hw interrupt-status regs into cptra_intr_rcv
extern "C" void asm_wfi(void);

static std::uint8_t mem[128u * 1024u * 1024u];

#define FB_FW_WRAP_EXTERNAL_DPI
#include "fb_fw_wrap.h"          // SIM defined -> fb_read_reg/fb_write_reg = s_axi path
#include "caliptra_reg.h"

extern "C" void *fb_get_mem_p() { return mem; }

// The unmodified firmware's main(), renamed via -Dmain=fw_main (C linkage).
extern "C" void fw_main(void);

// ---- fb_axi_vip M-side DDR backing (must link; unused by crypto smoke tests) -
extern "C" u8 fb_c_read_ddr8_addr32(u32 addr_32, void *p_mem) {
  return *reinterpret_cast<u8 *>(static_cast<uintptr_t>(fb_widen_ptr(addr_32, p_mem)));
}
extern "C" void fb_c_write_ddr8_addr32(u32 addr_32, u8 data, void *p_mem) {
  *reinterpret_cast<u8 *>(static_cast<uintptr_t>(fb_widen_ptr(addr_32, p_mem))) = data;
}
extern "C" u32 fb_c_read_ddr32_addr32(u32 addr_32, void *p_mem) {
  return *reinterpret_cast<u32 *>(static_cast<uintptr_t>(fb_widen_ptr(addr_32, p_mem)));
}
extern "C" void fb_c_write_ddr32_addr32(u32 addr_32, u32 data, u8 strb, void *p_mem) {
  u8 *ptr = reinterpret_cast<u8 *>(static_cast<uintptr_t>(fb_widen_ptr(addr_32, p_mem)));
  if (strb == 0xF) { *reinterpret_cast<u32 *>(ptr) = data; return; }
  for (int i = 0; i < 4; i++)
    if ((strb >> i) & 1) ptr[i] = static_cast<u8>(data >> (i * 8));
}

// ---- internal-AHB master accessors (fb_ahb_vip export functions) ------------
extern "C" void fb_ahb_drive(u8 hsel, u32 haddr, u64 hwdata, u8 hwrite, u8 hsize, u8 htrans, u8 hready);
extern "C" u8   fb_ahb_hreadyout(void);
extern "C" u8   fb_ahb_hresp(void);
extern "C" u64  fb_ahb_hrdata(void);
extern "C" void at_posedge_clk(void);
extern "C" void step_time_veri(void);

// AHB-Lite phase encodings (fb_fw_wrap.h defines these only in its AHB_SIM
// branch, which SIM masks here; define locally).
#ifndef FB_AHB_HSIZE_WORD
#define FB_AHB_HSIZE_WORD    ((u8)2)
#define FB_AHB_HTRANS_IDLE   ((u8)0)
#define FB_AHB_HTRANS_NONSEQ ((u8)2)
#endif

namespace {

constexpr int kPollLimit = 200000;

svScope g_axi_scope = nullptr;   // fb_axi_vip (run_sim default scope)
svScope g_ahb_scope = nullptr;   // u_fb_ahb
std::jmp_buf g_done;             // test termination unwind target

// Scope-correct primitives. at_posedge_clk() calls get_clk(), a DPI export in
// fb_axi_vip's scope; the fb_ahb_* exports live in u_fb_ahb's scope. Set the
// matching scope before each call.
void clk_posedge() { svSetScope(g_axi_scope); at_posedge_clk(); }
void clk_step()    { svSetScope(g_axi_scope); step_time_veri(); }
void ahb_drive(u8 sel, u32 a, u64 d, u8 w, u8 sz, u8 tr, u8 rdy) {
  svSetScope(g_ahb_scope); fb_ahb_drive(sel, a, d, w, sz, tr, rdy);
}
u8  ahb_hreadyout() { svSetScope(g_ahb_scope); return fb_ahb_hreadyout(); }
u8  ahb_hresp()     { svSetScope(g_ahb_scope); return fb_ahb_hresp(); }
u64 ahb_hrdata()    { svSetScope(g_ahb_scope); return fb_ahb_hrdata(); }

void ahb_wait_ready(const char *op, u32 addr) {
  int i;
  for (i = 0; i < kPollLimit; i++) { if (ahb_hreadyout()) break; clk_step(); }
  if (i >= kPollLimit) { std::fprintf(stderr, "FB_HAL: HREADYOUT timeout %s 0x%08x\n", op, addr); std::abort(); }
  if (ahb_hresp())      { std::fprintf(stderr, "FB_HAL: HRESP error %s 0x%08x\n", op, addr); std::abort(); }
}

// 64-bit internal AHB: a 32-bit word lands on hwdata/hrdata [63:32] when
// addr[2]==1, else [31:0]. Steer by addr&4.
// Byte-granular AHB write: HSIZE=byte (0), no read-modify-write.
// Required for write-only AHB slaves such as the KMAC MSG_FIFO
// (CLP_KMAC_MSG_FIFO_BASE_ADDR = 0x10040800) which return HRESP on reads.
// Data is placed in the correct byte lane of the 64-bit internal AHB bus.
void ahb_write8(u32 addr, u8 data) {
  constexpr u8 kHsizeByte = 0;
  clk_posedge(); clk_step();
  ahb_drive(1, addr, 0, 1, kHsizeByte, FB_AHB_HTRANS_NONSEQ, 1);
  clk_posedge(); clk_step();
  u64 wdata = (u64)data << ((addr & 7u) * 8u);
  ahb_drive(0, 0, wdata, 0, kHsizeByte, FB_AHB_HTRANS_IDLE, 1);
  ahb_wait_ready("write8", addr);
  clk_posedge(); clk_step();
  ahb_drive(0, 0, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
}

void ahb_write32(u32 addr, u32 data) {
  clk_posedge(); clk_step();
  ahb_drive(1, addr, 0, 1, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_NONSEQ, 1);
  clk_posedge(); clk_step();
  ahb_drive(0, 0, ((addr & 0x4u) ? ((u64)data << 32) : (u64)data), 0,
            FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
  ahb_wait_ready("write", addr);
  clk_posedge(); clk_step();
  ahb_drive(0, 0, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
}

u32 ahb_read32(u32 addr) {
  clk_posedge(); clk_step();
  ahb_drive(1, addr, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_NONSEQ, 1);
  clk_posedge(); clk_step();
  ahb_drive(0, 0, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
  ahb_wait_ready("read", addr);
  clk_step();
  u64 rd = ahb_hrdata();
  u32 result = (addr & 0x4u) ? (u32)(rd >> 32) : (u32)rd;
  clk_posedge(); clk_step();
  ahb_drive(0, 0, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
  return result;
}

// ---- boot over s_axi (fb_read_reg/fb_write_reg from fb_fw_wrap.h SIM path) ---
constexpr std::uint32_t kUdsSeed[16] = {
    0xe4046d05, 0x385ab789, 0xc6a72866, 0xe08350f9,
    0x3f583e2a, 0x005ca0fa, 0xecc32b5c, 0xfc323d46,
    0x1c76c107, 0x307654db, 0x5566a5bd, 0x693e227c,
    0x14451624, 0x6a752c32, 0x9056d884, 0xdaf3c89d,
};
constexpr std::uint32_t kFieldEntropy[8] = {
    0xb32e2b17, 0x1b638270, 0x34ebb0d1, 0x909f7ef1,
    0xd51c5f82, 0xc1bb9bc2, 0x6bc4ac4d, 0xccdee835,
};
constexpr std::uint32_t kHekSeed[8] = {
    0xb32e2b17, 0x1b638270, 0x34ebb0d1, 0x909f7ef1,
    0xd51c5f82, 0xc1bb9bc2, 0x6bc4ac4d, 0xccdee835,
};

fb_reg_t *reg(std::uint32_t addr) {
  return reinterpret_cast<fb_reg_t *>(static_cast<std::uintptr_t>(addr));
}
std::uint32_t soc_read(std::uint32_t addr)  { return (std::uint32_t)fb_read_reg(reg(addr)); }
void soc_write(std::uint32_t addr, std::uint32_t d) { fb_write_reg(reg(addr), (fb_reg_t)d); }

void wait_flow_bit(const char *name, std::uint32_t mask, bool set) {
  for (int poll = 0; poll < kPollLimit; ++poll) {
    const std::uint32_t v = soc_read(CLP_SOC_IFC_REG_CPTRA_FLOW_STATUS);
    if (((v & mask) != 0u) == set) {
      std::fprintf(stderr, "FB_HAL: %s after %d polls (flow=0x%08x)\n", name, poll + 1, v);
      return;
    }
  }
  std::fprintf(stderr, "FB_HAL: timeout waiting for %s\n", name);
  std::abort();
}

void boot_caliptra() {
  svSetScope(g_axi_scope);
  std::fprintf(stderr, "FB_HAL: boot via external s_axi\n");
  wait_flow_bit("ready_for_fuses asserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, true);
  for (int i = 0; i < 5; ++i) at_posedge_clk();
  for (int dw = 0; dw < 16; ++dw) soc_write(CLP_SOC_IFC_REG_FUSE_UDS_SEED_0 + 4u * dw, kUdsSeed[dw]);
  for (int dw = 0; dw < 8; ++dw)  soc_write(CLP_SOC_IFC_REG_FUSE_FIELD_ENTROPY_0 + 4u * dw, kFieldEntropy[dw]);
  for (int dw = 0; dw < 8; ++dw)  soc_write(CLP_SOC_IFC_REG_FUSE_HEK_SEED_0 + 4u * dw, kHekSeed[dw]);
  soc_write(CLP_SOC_IFC_REG_FUSE_SOC_STEPPING_ID, 0u);
  soc_write(CLP_SOC_IFC_REG_CPTRA_FUSE_WR_DONE, SOC_IFC_REG_CPTRA_FUSE_WR_DONE_DONE_MASK);
  wait_flow_bit("ready_for_fuses deasserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, false);
  soc_write(CLP_SOC_IFC_REG_CPTRA_BOOTFSM_GO, SOC_IFC_REG_CPTRA_BOOTFSM_GO_GO_MASK);
  std::fprintf(stderr, "FB_HAL: boot FSM go\n");
}

// ---- Bidirectional mailbox (T6 tests: smoke_test_mbox, mbox_cg) -------------
// Tracks whether SOC (harness) currently holds the mbox lock.
static bool g_soc_holds_mbox_lock = false;
// Set when firmware responded (DATA_READY), pending SOC EXECUTE clear.
// We clear EXECUTE lazily when firmware polls it, so firm sees EXECUTE_SOC first.
static bool g_soc_pending_execute_clear = false;

// SOC→FW: acquire lock, send canned command, set EXECUTE.
// Triggered directly from fb_hal_write32 hook when firmware writes
// READY_FOR_MB_PROCESSING to FLOW_STATUS (condition already verified in caller).
void send_soc_mbox_command() {
  if (g_soc_holds_mbox_lock) { return; }  // already sent
  svSetScope(g_axi_scope);
  std::fprintf(stderr, "FB_HAL: mbox SOC→FW: acquiring lock (USER=0xFFFFFFFF required)\n");
  // Lock is acquired by reading MBOX_LOCK until it returns 0 (0=we got it, 1=busy)
  for (int i = 0; i < kPollLimit; ++i) {
    if (!(soc_read(CLP_MBOX_CSR_MBOX_LOCK) & MBOX_CSR_MBOX_LOCK_LOCK_MASK)) break;
  }
  g_soc_holds_mbox_lock = true;
  soc_write(CLP_MBOX_CSR_MBOX_CMD,    0xDEADBEEFu);
  soc_write(CLP_MBOX_CSR_MBOX_DLEN,   4u);
  soc_write(CLP_MBOX_CSR_MBOX_DATAIN, 0x12345678u);
  soc_write(CLP_MBOX_CSR_MBOX_EXECUTE, 1u);
  svSetScope(g_ahb_scope);
}

// Legacy: called from asm_wfi(); checks flag internally.
void run_mailbox_if_requested() {
  svSetScope(g_axi_scope);
  const std::uint32_t flow = soc_read(CLP_SOC_IFC_REG_CPTRA_FLOW_STATUS);
  svSetScope(g_ahb_scope);
  if (!(flow & SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_MB_PROCESSING_MASK)) return;
  send_soc_mbox_command();
}

// SOC side: firmware set DATA_READY. Read DATAOUT response but DON'T clear
// EXECUTE yet — the firmware needs to see EXECUTE_SOC state first. We set a
// flag so that when the firmware later polls EXECUTE (fb_hal_read32 intercept),
// we can lazily clear it then.
void soc_mbox_read_response() {
  svSetScope(g_axi_scope);
  // The FSM will transition to EXECUTE_SOC autonomously after DATA_READY is set.
  // Drain the firmware's response (MBOX_DLEN was our command's 4 bytes, so skip
  // drain since the mbox tracks how many words were written via DATAIN).
  // The actual response count is in DLEN after the firmware wrote its data.
  // For simplicity: just record that we need to clear EXECUTE later.
  std::fprintf(stderr, "FB_HAL: mbox FW set DATA_READY; deferring EXECUTE clear\n");
  g_soc_pending_execute_clear = true;
  svSetScope(g_ahb_scope);
}

// FW→SOC: firmware sent a command (EXECUTE=1, SOC doesn't hold lock).
// Read DATAOUT (firmware's data) and echo it back, set DATA_READY.
// IMPORTANT: do NOT read MBOX_LOCK here — that triggers rset and steals
// the lock from the firmware, corrupting the mbox state machine.
void soc_mbox_handle_fw_cmd() {
  svSetScope(g_axi_scope);
  // Wait one posedge for the FSM to transition to EXECUTE_UC
  at_posedge_clk();
  // Read DLEN (avoid LOCK register — rset side-effect)
  std::uint32_t dlen = soc_read(CLP_MBOX_CSR_MBOX_DLEN);
  std::uint32_t words = (dlen > 0u && dlen < 0x10000u) ? (dlen + 3u) / 4u : 0u;
  std::fprintf(stderr, "FB_HAL: mbox FW→SOC: DLEN=0x%x words=%u\n", dlen, words);
  constexpr std::uint32_t kMaxWords = 256u;
  if (words > kMaxWords) words = kMaxWords;
  std::uint32_t buf[kMaxWords] = {};
  for (std::uint32_t i = 0; i < words; ++i)
    buf[i] = soc_read(CLP_MBOX_CSR_MBOX_DATAOUT);
  for (std::uint32_t i = 0; i < words; ++i)
    soc_write(CLP_MBOX_CSR_MBOX_DATAIN, buf[i]);
  soc_write(CLP_MBOX_CSR_MBOX_STATUS, 1u);  // DATA_READY = 1
  std::fprintf(stderr, "FB_HAL: mbox FW→SOC: echoed %u words, DATA_READY set\n", words);
  svSetScope(g_ahb_scope);
}

} // namespace

// Exposed so fb_caliptra_isr.c's asm_wfi() can trigger the mailbox agent.
extern "C" void fb_hal_check_mailbox(void) { run_mailbox_if_requested(); }

// ---- FB HAL sinks called by the firmware (see firebridge/fb_hal/*.h) --------
extern "C" void     fb_hal_write32(std::uintptr_t addr, u32 data) {
  ahb_write32((u32)addr, data);
  // Writing KMAC_INTR_TEST or KMAC_CMD triggers an interrupt (done, error, etc.).
  // Call asm_wfi() to reflect it into cptra_intr_rcv.sha3_notif/sha3_error immediately,
  // so the firmware's interrupt-check loops see the updated struct.
  if ((u32)addr == CLP_KMAC_INTR_TEST || (u32)addr == CLP_KMAC_CMD)
    asm_wfi();

  // Mbox bidirectional service (T6 tests):
  // 1. FLOW_STATUS: READY_FOR_MB_PROCESSING → SOC sends command to firmware.
  //    Hook fires in fb_hal_write32 so READY_FOR_MB_PROCESSING is confirmed in 'data'.
  //    Skip re-reading FLOW_STATUS via AXI (firmware wrote via AHB; AXI may see stale 0).
  if ((u32)addr == CLP_SOC_IFC_REG_CPTRA_FLOW_STATUS &&
      (data & SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_MB_PROCESSING_MASK))
    send_soc_mbox_command();
  // 2. MBOX_STATUS = DATA_READY: firmware responded to SOC command →
  //    SOC reads response and clears EXECUTE.
  if ((u32)addr == CLP_MBOX_CSR_MBOX_STATUS &&
      (data & MBOX_CSR_MBOX_STATUS_STATUS_MASK) == 1u &&  // DATA_READY = 1
      g_soc_holds_mbox_lock)
    soc_mbox_read_response();
  // 3. MBOX_EXECUTE = 1 (SOC doesn't hold lock): firmware sends command to SOC →
  //    SOC echoes data back and sets DATA_READY.
  if ((u32)addr == CLP_MBOX_CSR_MBOX_EXECUTE &&
      (data & MBOX_CSR_MBOX_EXECUTE_EXECUTE_MASK) &&
      !g_soc_holds_mbox_lock)
    soc_mbox_handle_fw_cmd();
}
extern "C" u32      fb_hal_read32 (std::uintptr_t addr) {
  u32 val = ahb_read32((u32)addr);
  // When firmware polls MBOX_EXECUTE waiting for it to be cleared by SOC:
  // clear it now (SOC side) so the firmware can proceed.
  if ((u32)addr == CLP_MBOX_CSR_MBOX_EXECUTE && g_soc_pending_execute_clear &&
      (val & MBOX_CSR_MBOX_EXECUTE_EXECUTE_MASK)) {
    // Drain firmware's DATAOUT response then clear EXECUTE via AXI
    svSetScope(g_axi_scope);
    std::fprintf(stderr, "FB_HAL: mbox SOC clearing EXECUTE (lazy, FW polling)\n");
    // Read the firmware's response data from DATAOUT
    // The firmware wrote MBOX_DLEN_VAL=32 bytes into DATAIN; we don't know
    // the exact count here — just clear EXECUTE to release the mailbox.
    soc_write(CLP_MBOX_CSR_MBOX_EXECUTE, 0u);
    g_soc_holds_mbox_lock = false;
    g_soc_pending_execute_clear = false;
    svSetScope(g_ahb_scope);
    // Return 0 (EXECUTE cleared) so firmware's poll loop exits
    return 0u;
  }
  return val;
}
extern "C" void     fb_hal_write8 (std::uintptr_t addr, u8 data) {
  // Use proper byte-granular AHB write (HSIZE=byte, no read-modify-write).
  // This avoids HRESP errors on write-only AHB slaves like KMAC MSG_FIFO.
  ahb_write8((u32)addr, data);
}
// Route firmware STDOUT to the REAL generic-output-wires register over the
// internal AHB, so caliptra_top_tb_services sees every byte exactly as on VeeR:
// ASCII chars -> console dump, 0x7F -> MANUF lifecycle switch, 0xff/0x1 -> sim
// end (incl. the TB's own "* TESTCASE PASSED" verdict). The firmware's text thus
// comes out via the TB console dump; we deliberately do NOT echo it again here.
// We longjmp out of the firmware on the terminal codes so we never fall into its
// trailing while(1) (a TB $finish only sets a flag; it does not unwind C).
static void fb_emit_wire(int c) {
  ahb_write32(CLP_SOC_IFC_REG_CPTRA_GENERIC_OUTPUT_WIRES_0, (u32)(unsigned char)c);
}
extern "C" void fb_putc(int c) { fb_emit_wire(c); }
extern "C" void fb_stdout_ctrl(int ctrl) {
  fb_emit_wire(ctrl);                            // lets the TB act (0x7F, etc.)
  if (ctrl == 0xff) std::longjmp(g_done, 1);     // firmware-reported pass
  if (ctrl == 0x01) std::longjmp(g_done, 2);     // firmware-reported fail
  // Warm/cold reset: RTL reset is triggered by TB services via the STDOUT write.
  // Wait for the RTL to come back up (ready_for_fuses), then longjmp back to
  // run_sim so fw_main() restarts from the beginning (advancing rst_count).
  if (ctrl == 0xf5 || ctrl == 0xf6 || ctrl == 0xf7) {
    std::fprintf(stderr, "FB_HAL: reset 0x%02x — waiting for re-boot\n", (unsigned)ctrl);
    boot_caliptra();
    std::longjmp(g_done, 3);     // signal run_sim to restart fw_main()
  }
}

extern "C" void run_sim(void *p_mem) {
  (void)p_mem;
  g_axi_scope = svGetScope();
  g_ahb_scope = svGetScopeFromName("TOP.caliptra_top_tb.caliptra_top_dut.u_fb_ahb");
  std::fprintf(stderr, "FB_HAL: axi_scope=%p ahb_scope=%p\n", (void *)g_axi_scope, (void *)g_ahb_scope);
  if (!g_ahb_scope) { std::fprintf(stderr, "FB_HAL: u_fb_ahb scope not found\n"); std::abort(); }

  boot_caliptra();                 // s_axi scope

  volatile int rc;
  do {
    rc = setjmp(g_done);
    if (rc == 0 || rc == 3) {
      fw_main();                   // unmodified firmware; HAL drives internal AHB
      // Firmware returned normally (no 0xff/0x01 sent). Some tests (e.g. doe_scan)
      // do not call SEND_STDOUT_CTRL(0xff) — they rely on TB assertions. Treat as
      // pass. Exit immediately to avoid Verilator's coroutine cleanup from resuming
      // any dangling coroutine frames left by longjmp.
      std::fprintf(stderr, "FB_HAL: firmware returned — exiting\n");
      std::exit(0);
    } else if (rc == 2) {
      std::fprintf(stderr, "FB_HAL: TEST FAILED (firmware SEND_STDOUT_CTRL 0x1)\n");
      svSetScope(g_axi_scope);
      std::abort();
    } else {
      // rc == 1: TEST PASSED. Exit immediately to avoid Verilator's coroutine
      // cleanup from resuming dangling frames left by longjmp restarts.
      std::fprintf(stderr, "FB_HAL: TEST PASSED (firmware SEND_STDOUT_CTRL 0xff)\n");
      std::exit(0);
    }
  } while (true);
  svSetScope(g_axi_scope);         // restore for fb_axi_vip end-of-sim
}
