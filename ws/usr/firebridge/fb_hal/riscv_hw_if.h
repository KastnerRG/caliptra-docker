// FireBridge HAL replacement for the Caliptra test-suite riscv_hw_if.h.
// Put this directory FIRST on the include path under -DFIREBRIDGE so the
// unmodified firmware's lsu_* register accesses are routed to the FireBridge
// AHB master (driven from C in the harness) instead of dereferencing host
// addresses. Signatures match the upstream header exactly.
#ifndef RISCV_HW_IF_H
#define RISCV_HW_IF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
// Implemented by the FireBridge harness (fb_harness.cpp). These perform a real
// AHB-Lite transaction over the internal Caliptra bus via fb_ahb_vip.
void     fb_hal_write32(uintptr_t addr, uint32_t data);
uint32_t fb_hal_read32(uintptr_t addr);
void     fb_hal_write8(uintptr_t addr, uint8_t data);
#ifdef __cplusplus
}
#endif

static inline void lsu_write_32(uintptr_t addr, uint32_t data) { fb_hal_write32(addr, data); }
static inline uint32_t lsu_read_32(uintptr_t addr) { return fb_hal_read32(addr); }
static inline void lsu_write_8(uintptr_t addr, uint8_t data) { fb_hal_write8(addr, data); }

// Privileged-instruction wrappers used by the interrupt-wait loops. There is no
// RISC-V core under FireBridge, so asm_wfi() is a polled software-interrupt
// service (implemented in fb_caliptra_isr.c: it reflects each crypto block's
// interrupt-status register into cptra_intr_rcv, like the real ISRs would), and
// asm_nop() is a no-op. The unmodified wait loops then terminate as on VeeR.
#ifdef __cplusplus
extern "C" {
#endif
void asm_wfi(void);
#ifdef __cplusplus
}
#endif
#define asm_nop() ((void)0)

#endif /* RISCV_HW_IF_H */
