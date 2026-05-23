#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "svdpi.h"
#include "verilated.h"

static std::uint8_t mem[4096];

#define FB_FW_WRAP_EXTERNAL_DPI
#include "fb_fw_wrap.h"

extern "C" void *fb_get_mem_p() {
  return mem;
}

extern "C" void at_posedge_clk();

namespace {
svScope g_fb_scope = nullptr;

void enter_fb_scope() {
  svSetScope(g_fb_scope);
  Verilated::dpiScope(static_cast<const VerilatedScope *>(g_fb_scope));
}

fb_reg_t *reg(std::uint32_t addr) {
  return reinterpret_cast<fb_reg_t *>(static_cast<std::uintptr_t>(addr));
}

std::uint32_t read32(std::uint32_t addr) {
  enter_fb_scope();
  return static_cast<std::uint32_t>(fb_read_reg(reg(addr)));
}

void write32(std::uint32_t addr, std::uint32_t data) {
  enter_fb_scope();
  fb_write_reg(reg(addr), static_cast<fb_reg_t>(data));
}

void expect32(std::uint32_t addr, std::uint32_t expected) {
  const std::uint32_t actual = read32(addr);
  if (actual != expected) {
    std::fprintf(stderr, "FB_AHB selfcheck: addr 0x%08x expected 0x%08x got 0x%08x\n",
                 addr, expected, actual);
    std::abort();
  }
}

} // namespace

extern "C" int run_sim(void *p_mem) {
  (void)p_mem;
  g_fb_scope = svGetScopeFromName("TOP.ahb_selfcheck_tb.fb_ahb_i");
  enter_fb_scope();
  write32(0x00, 0x12345678);
  write32(0x04, 0xa5a55a5a);
  expect32(0x00, 0x12345678);
  expect32(0x04, 0xa5a55a5a);
  write32(0x00, 0xfeedc0de);
  expect32(0x00, 0xfeedc0de);

  for (int cycle = 0; cycle < 4; ++cycle) {
    at_posedge_clk();
  }
  return 0;
}
