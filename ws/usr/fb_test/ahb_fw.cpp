// Mode-B FireBridge driver: boot Caliptra over external s_axi (via fb_axi_vip),
// then run the test firmware over the INTERNAL AHB bus (via fb_ahb_vip, which
// replaces the bypassed VeeR). Two DPI scopes are in play:
//   - fb_axi_vip  : owns run_sim/clock; s_axi register access (boot)
//   - u_fb_ahb    : internal AHB master; crypto register access
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "svdpi.h"

static std::uint8_t mem[128u * 1024u * 1024u];

#define FB_FW_WRAP_EXTERNAL_DPI
#include "fb_fw_wrap.h"          // SIM defined -> fb_read_reg/fb_write_reg = s_axi path
#include "caliptra_reg.h"

extern "C" void *fb_get_mem_p() { return mem; }

// ---- fb_axi_vip M-side DDR backing (unused by sha256 but must link) ---------
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

// fb_fw_wrap.h defines these only in its AHB_SIM branch, which is not taken here
// (SIM wins, providing the s_axi boot path). Define them locally for AHB access.
#ifndef FB_AHB_HSIZE_WORD
#define FB_AHB_HSIZE_WORD    ((u8)2)
#define FB_AHB_HTRANS_IDLE   ((u8)0)
#define FB_AHB_HTRANS_NONSEQ ((u8)2)
#endif

namespace {

constexpr int kPollLimit = 200000;

svScope g_axi_scope = nullptr;   // fb_axi_vip (run_sim default scope)
svScope g_ahb_scope = nullptr;   // u_fb_ahb

// Scope-correct primitives. at_posedge_clk() calls get_clk(), a DPI export that
// lives in fb_axi_vip's scope; the fb_ahb_* exports live in u_fb_ahb's scope.
// So we set the matching scope before every call. (step_time_veri() makes no
// DPI-export call, but we keep it in the axi scope for consistency.)
void clk_posedge() { svSetScope(g_axi_scope); at_posedge_clk(); }
void clk_step()    { svSetScope(g_axi_scope); step_time_veri(); }
void ahb_drive(u8 sel, u32 a, u64 d, u8 w, u8 sz, u8 tr, u8 rdy) {
  svSetScope(g_ahb_scope); fb_ahb_drive(sel, a, d, w, sz, tr, rdy);
}
u8  ahb_hreadyout() { svSetScope(g_ahb_scope); return fb_ahb_hreadyout(); }
u8  ahb_hresp()     { svSetScope(g_ahb_scope); return fb_ahb_hresp(); }
u64 ahb_hrdata()    { svSetScope(g_ahb_scope); return fb_ahb_hrdata(); }

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
      std::fprintf(stderr, "FB_AHB: %s after %d polls (flow=0x%08x)\n", name, poll + 1, v);
      return;
    }
  }
  std::fprintf(stderr, "FB_AHB: timeout waiting for %s\n", name);
  std::abort();
}

void boot_caliptra() {
  std::fprintf(stderr, "FB_AHB: boot via external s_axi\n");
  wait_flow_bit("ready_for_fuses asserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, true);
  for (int i = 0; i < 5; ++i) at_posedge_clk();
  for (int dw = 0; dw < 16; ++dw) soc_write(CLP_SOC_IFC_REG_FUSE_UDS_SEED_0 + 4u * dw, kUdsSeed[dw]);
  for (int dw = 0; dw < 8; ++dw)  soc_write(CLP_SOC_IFC_REG_FUSE_FIELD_ENTROPY_0 + 4u * dw, kFieldEntropy[dw]);
  for (int dw = 0; dw < 8; ++dw)  soc_write(CLP_SOC_IFC_REG_FUSE_HEK_SEED_0 + 4u * dw, kHekSeed[dw]);
  soc_write(CLP_SOC_IFC_REG_FUSE_SOC_STEPPING_ID, 0u);
  soc_write(CLP_SOC_IFC_REG_CPTRA_FUSE_WR_DONE, SOC_IFC_REG_CPTRA_FUSE_WR_DONE_DONE_MASK);
  wait_flow_bit("ready_for_fuses deasserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, false);
  soc_write(CLP_SOC_IFC_REG_CPTRA_BOOTFSM_GO, SOC_IFC_REG_CPTRA_BOOTFSM_GO_GO_MASK);
  std::fprintf(stderr, "FB_AHB: boot FSM go\n");
}

// ---- crypto over internal AHB (scope switched to u_fb_ahb) -------------------
void ahb_wait_ready(const char *op, u32 addr) {
  int i;
  for (i = 0; i < kPollLimit; i++) { if (ahb_hreadyout()) break; clk_step(); }
  if (i >= kPollLimit) { std::fprintf(stderr, "FB_AHB: HREADYOUT timeout %s 0x%08x\n", op, addr); std::abort(); }
  if (ahb_hresp())      { std::fprintf(stderr, "FB_AHB: HRESP error %s 0x%08x\n", op, addr); std::abort(); }
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

void ahb_poll(u32 addr, u32 mask) {
  for (int i = 0; i < kPollLimit; i++) if (ahb_read32(addr) & mask) return;
  std::fprintf(stderr, "FB_AHB: timeout polling 0x%08x mask 0x%08x\n", addr, mask);
  std::abort();
}

void sha256_abc_test() {
  static const u32 block[16] = {
    0x61626380u, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x00000018u};
  static const u32 expected[8] = {
    0xBA7816BFu, 0x8F01CFEAu, 0x414140DEu, 0x5DAE2223u,
    0xB00361A3u, 0x96177A9Cu, 0xB410FF61u, 0xF20015ADu};
  std::fprintf(stderr, "FB_AHB: SHA256 over internal AHB\n");
  ahb_poll(CLP_SHA256_REG_SHA256_STATUS, 0x1u);                 // READY
  for (int i = 0; i < 16; i++) ahb_write32(CLP_SHA256_REG_SHA256_BLOCK_0 + i * 4, block[i]);
  ahb_write32(CLP_SHA256_REG_SHA256_CTRL, 0x5u);                // INIT | MODE=SHA256
  ahb_poll(CLP_SHA256_REG_SHA256_STATUS, 0x2u);                 // VALID
  for (int i = 0; i < 8; i++) {
    u32 got = ahb_read32(CLP_SHA256_REG_SHA256_DIGEST_0 + i * 4);
    if (got != expected[i]) {
      std::fprintf(stderr, "FB_AHB sha256 FAIL: digest[%d] exp 0x%08x got 0x%08x\n", i, expected[i], got);
      std::abort();
    }
  }
  std::fprintf(stderr, "FB_AHB sha256 PASS\n");
}

void sha512_abc_test() {
  // SHA512("abc"): single 1024-bit padded block (32 words), MSB word first.
  static u32 block[32] = {0};
  block[0]  = 0x61626380u;
  block[31] = 0x00000018u;
  static const u32 expected[16] = {  // DDAF35A1...A54CA49F
    0xDDAF35A1u, 0x93617ABAu, 0xCC417349u, 0xAE204131u,
    0x12E6FA4Eu, 0x89A97EA2u, 0x0A9EEEE6u, 0x4B55D39Au,
    0x2192992Au, 0x274FC1A8u, 0x36BA3C23u, 0xA3FEEBBDu,
    0x454D4423u, 0x643CE80Eu, 0x2A9AC94Fu, 0xA54CA49Fu};
  std::fprintf(stderr, "FB_AHB: SHA512 over internal AHB\n");
  ahb_poll(CLP_SHA512_REG_SHA512_STATUS, 0x1u);                       // READY
  for (int i = 0; i < 32; i++) ahb_write32(CLP_SHA512_REG_SHA512_BLOCK_0 + i * 4, block[i]);
  ahb_write32(CLP_SHA512_REG_SHA512_CTRL, 0xDu);                      // INIT | MODE=SHA512(3)
  ahb_poll(CLP_SHA512_REG_SHA512_STATUS, 0x2u);                       // VALID
  for (int i = 0; i < 16; i++) {
    u32 got = ahb_read32(CLP_SHA512_REG_SHA512_DIGEST_0 + i * 4);
    if (got != expected[i]) {
      std::fprintf(stderr, "FB_AHB sha512 FAIL: digest[%d] exp 0x%08x got 0x%08x\n", i, expected[i], got);
      std::abort();
    }
  }
  std::fprintf(stderr, "FB_AHB sha512 PASS\n");
}

void hmac384_test() {
  // Vectors copied verbatim from smoke_test_hmac.c (HMAC384, direct registers).
  static const u32 key[12] = {
    0x0b0b0b0b, 0x0b0b0b0b, 0x0b0b0b0b, 0x0b0b0b0b,
    0x0b0b0b0b, 0x0b0b0b0b, 0x0b0b0b0b, 0x0b0b0b0b,
    0x0b0b0b0b, 0x0b0b0b0b, 0x0b0b0b0b, 0x0b0b0b0b};
  static u32 block[32] = {0};
  block[0] = 0x48692054u; block[1] = 0x68657265u; block[2] = 0x80000000u; block[31] = 0x00000440u;
  static const u32 lfsr[12] = {
    0xC8F518D4u, 0xF3AA1BD4u, 0x6ED56C1Cu, 0x3C9E16FBu, 0x800AF504u, 0xC8F518D4u,
    0xF3AA1BD4u, 0x6ED56C1Cu, 0x3C9E16FBu, 0x800AF504u, 0xC8F518D4u, 0xF3AA1BD4u};
  static const u32 expected[12] = {
    0xb6a8d563u, 0x6f5c6a72u, 0x24f9977du, 0xcf7ee6c7u, 0xfb6d0c48u, 0xcbdee973u,
    0x7a959796u, 0x489bddbcu, 0x4c5df61du, 0x5b3297b4u, 0xfb68dab9u, 0xf1b582c2u};
  std::fprintf(stderr, "FB_AHB: HMAC384 over internal AHB\n");
  ahb_poll(CLP_HMAC_REG_HMAC512_STATUS, 0x1u);                          // READY
  for (int i = 0; i < 12; i++) ahb_write32(CLP_HMAC_REG_HMAC512_KEY_0 + i * 4, key[i]);
  for (int i = 0; i < 32; i++) ahb_write32(CLP_HMAC_REG_HMAC512_BLOCK_0 + i * 4, block[i]);
  for (int i = 0; i < 12; i++) ahb_write32(CLP_HMAC_REG_HMAC512_LFSR_SEED_0 + i * 4, lfsr[i]);
  ahb_write32(CLP_HMAC_REG_HMAC512_CTRL, 0x1u);                         // INIT | MODE=HMAC384(0)
  ahb_poll(CLP_HMAC_REG_HMAC512_STATUS, 0x2u);                          // VALID
  for (int i = 0; i < 12; i++) {
    u32 got = ahb_read32(CLP_HMAC_REG_HMAC512_TAG_0 + i * 4);
    if (got != expected[i]) {
      std::fprintf(stderr, "FB_AHB hmac FAIL: tag[%d] exp 0x%08x got 0x%08x\n", i, expected[i], got);
      std::abort();
    }
  }
  std::fprintf(stderr, "FB_AHB hmac PASS\n");
}

} // namespace

extern "C" void run_sim(void *p_mem) {
  (void)p_mem;
  g_axi_scope = svGetScope();
  g_ahb_scope = svGetScopeFromName("TOP.caliptra_top_tb.caliptra_top_dut.u_fb_ahb");
  std::fprintf(stderr, "FB_AHB: axi_scope=%p ahb_scope=%p\n", (void *)g_axi_scope, (void *)g_ahb_scope);
  if (!g_ahb_scope) { std::fprintf(stderr, "FB_AHB: u_fb_ahb scope not found\n"); std::abort(); }

  boot_caliptra();                 // s_axi scope

  // Crypto over internal AHB. Per-test routine selected by -DFB_TEST_<TESTNAME>
  // (the scope-correct wrappers manage axi/ahb scope switching internally).
#if defined(FB_TEST_smoke_test_sha512)
  sha512_abc_test();
#elif defined(FB_TEST_smoke_test_hmac)
  hmac384_test();
#elif defined(FB_TEST_smoke_test_sha256)
  sha256_abc_test();
#else
  std::fprintf(stderr, "FB_AHB: no AHB test routine compiled in (define FB_TEST_<name>)\n");
  std::abort();
#endif
  svSetScope(g_axi_scope);
}
