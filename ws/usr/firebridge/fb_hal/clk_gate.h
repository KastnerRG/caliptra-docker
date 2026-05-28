// FireBridge stub for clk_gate.h — host (x86) compilation.
// Under FireBridge there is no VeeR core, so machine-timer and halt operations
// are no-ops. This stub shadows libs/clk_gate/clk_gate.h via -I fb_hal/ first.
#ifndef CLK_GATE_H
#define CLK_GATE_H

#include <stdint.h>

static inline void set_mit0_and_halt_core(uint32_t mitb0, uint32_t mie_en) {
    (void)mitb0; (void)mie_en;
}
static inline void set_mit0(uint32_t mitb0, uint32_t mie_en) {
    (void)mitb0; (void)mie_en;
}
static inline void halt_core(void) {}

#endif /* CLK_GATE_H */
