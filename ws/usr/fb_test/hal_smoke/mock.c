// Standalone shake-out harness for the FireBridge firmware HAL. It compiles the
// UNMODIFIED smoke_test_sha256.c + sha256.c against the FireBridge HAL headers
// and a mock register file (no Verilator), to prove the firmware builds, links,
// and runs to PASS natively. The mock emulates just enough SHA256 behaviour:
// STATUS reports READY, and writing CTRL.INIT latches VALID + the known "abc"
// digest. Replaced by the real fb_ahb_vip path in the Verilator build.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <setjmp.h>
#include "caliptra_reg.h"

// The firmware's main() is renamed via -Dmain=fw_main so this file can own the
// real entry point.
void fw_main(void);

static jmp_buf g_done;

void fb_putc(int c) { fputc(c, stderr); }

void fb_stdout_ctrl(int ctrl) {
    // 0xff = test requests pass-termination; 0x1 = fail. Both unwind to main().
    if (ctrl == 0xff) longjmp(g_done, 1);
    if (ctrl == 0x1)  longjmp(g_done, 2);
    // other codes (ISR trace markers) are ignored under the mock
}

// --- mock SHA256 register file ----------------------------------------------
static uint32_t g_digest[8];
static uint32_t g_status = SHA256_REG_SHA256_STATUS_READY_MASK;

static const uint32_t kAbcDigest[8] = {
    0xBA7816BFu, 0x8F01CFEAu, 0x414140DEu, 0x5DAE2223u,
    0xB00361A3u, 0x96177A9Cu, 0xB410FF61u, 0xF20015ADu};

void fb_hal_write32(uintptr_t addr, uint32_t data) {
    if (addr == CLP_SHA256_REG_SHA256_CTRL && (data & SHA256_REG_SHA256_CTRL_INIT_MASK)) {
        for (int i = 0; i < 8; i++) g_digest[i] = kAbcDigest[i];
        g_status = SHA256_REG_SHA256_STATUS_READY_MASK | SHA256_REG_SHA256_STATUS_VALID_MASK;
    }
}

uint32_t fb_hal_read32(uintptr_t addr) {
    if (addr == CLP_SHA256_REG_SHA256_STATUS) return g_status;
    if (addr >= CLP_SHA256_REG_SHA256_DIGEST_0 && addr <= CLP_SHA256_REG_SHA256_DIGEST_7)
        return g_digest[(addr - CLP_SHA256_REG_SHA256_DIGEST_0) / 4];
    return 0;
}

void fb_hal_write8(uintptr_t addr, uint8_t data) { (void)addr; (void)data; }

int main(void) {
    int rc = setjmp(g_done);
    if (rc == 0) {
        fw_main();
        fprintf(stderr, "\n[mock] firmware returned without termination code\n");
        return 0;
    }
    fprintf(stderr, "\n[mock] %s\n", rc == 1 ? "PASS (0xff)" : "FAIL (0x1)");
    return rc == 1 ? 0 : 1;
}
