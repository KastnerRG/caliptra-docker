#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "svdpi.h"

static std::uint8_t mem[4096];

#define FB_FW_WRAP_EXTERNAL_DPI
#include "fb_fw_wrap.h"

extern "C" void *fb_get_mem_p() {
  return mem;
}

extern "C" void at_posedge_clk();

namespace {

// sha256_ctrl register offsets (from src/sha256/tb/sha256_ctrl_tb.sv).
constexpr std::uint32_t ADDR_CTRL    = 0x010;
constexpr std::uint32_t ADDR_STATUS  = 0x018;
constexpr std::uint32_t ADDR_BLOCK0  = 0x080;
constexpr std::uint32_t ADDR_DIGEST0 = 0x100;

constexpr std::uint32_t CTRL_INIT = 0x1;   // INIT=bit0
constexpr std::uint32_t CTRL_MODE = 0x4;   // MODE=bit2 (1 => SHA256, 0 => SHA224)

constexpr std::uint32_t STATUS_READY = 0x1; // bit0
constexpr std::uint32_t STATUS_VALID = 0x2; // bit1

fb_reg_t *reg(std::uint32_t addr) {
  return reinterpret_cast<fb_reg_t *>(static_cast<std::uintptr_t>(addr));
}

std::uint32_t read32(std::uint32_t addr) {
  return static_cast<std::uint32_t>(fb_read_reg(reg(addr)));
}

void write32(std::uint32_t addr, std::uint32_t data) {
  fb_write_reg(reg(addr), static_cast<fb_reg_t>(data));
}

void poll_until(std::uint32_t addr, std::uint32_t mask) {
  for (int i = 0; i < 100000; ++i) {
    if (read32(addr) & mask) return;
  }
  std::fprintf(stderr, "FB_AHB sha256 FAIL: timeout polling 0x%08x mask 0x%08x\n", addr, mask);
  std::abort();
}

} // namespace

extern "C" int run_sim(void *p_mem) {
  (void)p_mem;

  // SHA256("abc"): single 512-bit padded block, MSB word first.
  static const std::uint32_t block[16] = {
    0x61626380u, 0x00000000u, 0x00000000u, 0x00000000u,
    0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u,
    0x00000000u, 0x00000000u, 0x00000000u, 0x00000000u,
    0x00000000u, 0x00000000u, 0x00000000u, 0x00000018u,
  };
  static const std::uint32_t expected[8] = {
    0xBA7816BFu, 0x8F01CFEAu, 0x414140DEu, 0x5DAE2223u,
    0xB00361A3u, 0x96177A9Cu, 0xB410FF61u, 0xF20015ADu,
  };

  poll_until(ADDR_STATUS, STATUS_READY);

  for (int i = 0; i < 16; ++i) {
    write32(ADDR_BLOCK0 + i * 4, block[i]);
  }

  write32(ADDR_CTRL, CTRL_INIT | CTRL_MODE);

  poll_until(ADDR_STATUS, STATUS_VALID);

  for (int i = 0; i < 8; ++i) {
    const std::uint32_t got = read32(ADDR_DIGEST0 + i * 4);
    if (got != expected[i]) {
      std::fprintf(stderr,
                   "FB_AHB sha256 FAIL: digest[%d] expected 0x%08x got 0x%08x\n",
                   i, expected[i], got);
      std::abort();
    }
  }

  return 0;
}
