#include <cstdint>
#include <cstdio>
#include <cstdlib>

static std::uint8_t mem[128u * 1024u * 1024u];

#define FB_FW_WRAP_EXTERNAL_DPI
#include "fb_fw_wrap.h"
#include "caliptra_reg.h"

extern "C" void *fb_get_mem_p() {
  return mem;
}

extern "C" void at_posedge_clk();

extern "C" u8 fb_c_read_ddr8_addr32(u32 addr_32, void *p_mem) {
  const u64 addr = fb_widen_ptr(addr_32, p_mem);
  return *reinterpret_cast<u8 *>(static_cast<uintptr_t>(addr));
}

extern "C" void fb_c_write_ddr8_addr32(u32 addr_32, u8 data, void *p_mem) {
  const u64 addr = fb_widen_ptr(addr_32, p_mem);
  *reinterpret_cast<u8 *>(static_cast<uintptr_t>(addr)) = data;
}

extern "C" u32 fb_c_read_ddr32_addr32(u32 addr_32, void *p_mem) {
  const u64 addr = fb_widen_ptr(addr_32, p_mem);
  return *reinterpret_cast<u32 *>(static_cast<uintptr_t>(addr));
}

extern "C" void fb_c_write_ddr32_addr32(u32 addr_32, u32 data, u8 strb, void *p_mem) {
  u8 *ptr = reinterpret_cast<u8 *>(static_cast<uintptr_t>(fb_widen_ptr(addr_32, p_mem)));
  if (strb == 0xF) { *reinterpret_cast<u32 *>(ptr) = data; return; }
  for (int i = 0; i < 4; i++)
    if ((strb >> i) & 1) ptr[i] = static_cast<u8>(data >> (i * 8));
}

namespace {

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

constexpr int kPollLimit = 200000;

fb_reg_t *reg(std::uint32_t addr) {
  return reinterpret_cast<fb_reg_t *>(static_cast<std::uintptr_t>(addr));
}

std::uint32_t read32(std::uint32_t addr) {
  return static_cast<std::uint32_t>(fb_read_reg(reg(addr)));
}

void write32(std::uint32_t addr, std::uint32_t data) {
  fb_write_reg(reg(addr), static_cast<fb_reg_t>(data));
}

void wait_flow_bit(const char *name, std::uint32_t mask, bool set) {
  for (int poll = 0; poll < kPollLimit; ++poll) {
    const std::uint32_t value = read32(CLP_SOC_IFC_REG_CPTRA_FLOW_STATUS);
    if (((value & mask) != 0u) == set) {
      std::fprintf(stderr, "FB_AXI: %s after %d polls (flow=0x%08x)\n", name, poll + 1, value);
      return;
    }
  }
  std::fprintf(stderr, "FB_AXI: timeout waiting for %s\n", name);
  std::abort();
}

void write_fuses() {
  for (int dw = 0; dw < 16; ++dw) {
    write32(CLP_SOC_IFC_REG_FUSE_UDS_SEED_0 + 4u * dw, kUdsSeed[dw]);
  }

  for (int dw = 0; dw < 8; ++dw) {
    write32(CLP_SOC_IFC_REG_FUSE_FIELD_ENTROPY_0 + 4u * dw, kFieldEntropy[dw]);
  }

  for (int dw = 0; dw < 8; ++dw) {
    write32(CLP_SOC_IFC_REG_FUSE_HEK_SEED_0 + 4u * dw, kHekSeed[dw]);
  }

  write32(CLP_SOC_IFC_REG_FUSE_SOC_STEPPING_ID, 0u);
  write32(CLP_SOC_IFC_REG_CPTRA_FUSE_WR_DONE, SOC_IFC_REG_CPTRA_FUSE_WR_DONE_DONE_MASK);
}

} // namespace

extern "C" void run_sim(void *p_mem) {
  (void)p_mem;
  std::fprintf(stderr, "FB_AXI: starting Caliptra external AXI boot flow\n");
  wait_flow_bit("ready_for_fuses asserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, true);
  for (int cycle = 0; cycle < 5; ++cycle) {
    at_posedge_clk();
  }
  std::fprintf(stderr, "FB_AXI: writing fuse registers\n");
  write_fuses();
  wait_flow_bit("ready_for_fuses deasserted", SOC_IFC_REG_CPTRA_FLOW_STATUS_READY_FOR_FUSES_MASK, false);
  write32(CLP_SOC_IFC_REG_CPTRA_BOOTFSM_GO, SOC_IFC_REG_CPTRA_BOOTFSM_GO_GO_MASK);
  std::fprintf(stderr, "FB_AXI: boot flow complete; firmware owns pass/fail\n");
}
