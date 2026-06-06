// FireBridge HAL harness (Mode B, AHB-only). VeeR is held in reset; the tb's
// soc_bfm boots Caliptra over the external AXI as it normally would. Once boot
// completes, this file runs the UNMODIFIED test firmware natively on the host:
// the firmware's lsu_*/printf/SEND_STDOUT_CTRL are redirected through the FB
// HAL (firebridge/fb_hal/*.h) into this file, which performs real AHB-Lite
// transactions over the internal Caliptra bus via fb_ahb_vip (the bypassed
// VeeR's master, scope u_fb_ahb).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <csetjmp>
#include "svdpi.h"

// fb_caliptra_isr.c provides asm_wfi() which reflects hw interrupt-status regs into cptra_intr_rcv
extern "C" void asm_wfi(void);

static std::uint8_t mem[128u * 1024u * 1024u];

// Tells fb_fw_wrap.h that *this* TU provides fb_get_mem_p (below) instead of
// the header defining one against a `mem` symbol of its own assumed layout.
#define FB_FW_WRAP_EXTERNAL_DPI
#include "fb_fw_wrap.h"          // u8/u32/u64 typedefs (fb_read_reg/fb_write_reg unused here)
#include "caliptra_reg.h"

extern "C" void *fb_get_mem_p() { return mem; }

// The unmodified firmware's main(), renamed via -Dmain=fw_main (C linkage).
extern "C" void fw_main(void);

// ---- internal-AHB master accessors (fb_ahb_vip export functions) ------------
extern "C" void fb_ahb_drive(u8 hsel, u32 haddr, u64 hwdata, u8 hwrite, u8 hsize, u8 htrans, u8 hready);
extern "C" u8   fb_ahb_hreadyout(void);
extern "C" u8   fb_ahb_hresp(void);
extern "C" u64  fb_ahb_hrdata(void);
extern "C" void at_posedge_clk(void);
extern "C" void step_time_veri(void);

// AHB-Lite phase encodings (fb_fw_wrap.h defines these only in its AHB_SIM
// branch, which we don't select here; define locally).
#define FB_AHB_HSIZE_WORD    ((u8)2)
#define FB_AHB_HTRANS_IDLE   ((u8)0)
#define FB_AHB_HTRANS_NONSEQ ((u8)2)

namespace {

constexpr int kPollLimit = 200000;

svScope g_ahb_scope = nullptr;   // u_fb_ahb (run_sim's own scope)
std::jmp_buf g_done;             // test termination unwind target

void clk_posedge() { svSetScope(g_ahb_scope); at_posedge_clk(); }
void clk_step()    { svSetScope(g_ahb_scope); step_time_veri(); }
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

// ---- boot synchronization ----------------------------------------------------
// The tb's soc_bfm drives the external AXI exactly as it does in no-FB runs
// (writes fuses, FUSE_WR_DONE, BOOTFSM_GO). We just watch CPTRA_FLOW_STATUS
// over the internal AHB — the same register VeeR firmware would poll — for
// READY_FOR_FUSES to assert (boot started) then deassert (boot handshake done).
void wait_flow_bit(const char *name, std::uint32_t mask, bool set) {
  for (int poll = 0; poll < kPollLimit; ++poll) {
    const std::uint32_t v = ahb_read32(CLP_SOC_IFC_REG_CPTRA_FLOW_STATUS);
    if (((v & mask) != 0u) == set) {
      std::fprintf(stderr, "FB_HAL: %s after %d polls (flow=0x%08x)\n", name, poll + 1, v);
      return;
    }
  }
  std::fprintf(stderr, "FB_HAL: timeout waiting for %s\n", name);
  std::abort();
}

void wait_for_boot() {
  std::fprintf(stderr, "FB_HAL: waiting for tb soc_bfm to boot Caliptra\n");
  wait_flow_bit("ready_for_fuses asserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, true);
  wait_flow_bit("ready_for_fuses deasserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, false);
  for (int i = 0; i < 5; ++i) clk_posedge();
}

} // namespace

// ---- FB HAL sinks called by the firmware (see firebridge/fb_hal/*.h) --------
extern "C" void     fb_hal_write32(std::uintptr_t addr, u32 data) {
  ahb_write32((u32)addr, data);
  // Writing KMAC_INTR_TEST or KMAC_CMD triggers an interrupt (done, error, etc.).
  // Call asm_wfi() to reflect it into cptra_intr_rcv.sha3_notif/sha3_error immediately,
  // so the firmware's interrupt-check loops see the updated struct.
  if ((u32)addr == CLP_KMAC_INTR_TEST || (u32)addr == CLP_KMAC_CMD)
    asm_wfi();
}
extern "C" u32      fb_hal_read32 (std::uintptr_t addr) {
  return ahb_read32((u32)addr);
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
  // Wait for the RTL to come back up and soc_bfm to re-boot Caliptra, then
  // longjmp back to run_sim so fw_main() restarts from the beginning.
  if (ctrl == 0xf5 || ctrl == 0xf6 || ctrl == 0xf7) {
    std::fprintf(stderr, "FB_HAL: reset 0x%02x — waiting for re-boot\n", (unsigned)ctrl);
    wait_for_boot();
    std::longjmp(g_done, 3);     // signal run_sim to restart fw_main()
  }
}

extern "C" void run_sim(void *p_mem) {
  (void)p_mem;
  g_ahb_scope = svGetScope();
  std::fprintf(stderr, "FB_HAL: ahb_scope=%p\n", (void *)g_ahb_scope);

  wait_for_boot();

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
      std::abort();
    } else {
      // rc == 1: TEST PASSED. Exit immediately to avoid Verilator's coroutine
      // cleanup from resuming dangling frames left by longjmp restarts.
      std::fprintf(stderr, "FB_HAL: TEST PASSED (firmware SEND_STDOUT_CTRL 0xff)\n");
      std::exit(0);
    }
  } while (true);
}
