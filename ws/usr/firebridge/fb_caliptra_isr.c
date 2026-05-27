// FireBridge host-side replacement for the Caliptra test-suite caliptra_isr.c.
// Under FireBridge the firmware runs natively with no RISC-V core, so there is
// no PIC/PLIC to program: init_interrupts() is a no-op.
//
// The crypto libs wait on completion with the unmodified upstream loop
//   while (cptra_intr_rcv.<blk>_{error,notif} == 0) { asm_wfi(); ... asm_nop(); }
// On VeeR those flags are set by the per-source ISRs. With no core, asm_wfi() is
// the software stand-in: it reflects each crypto block's raw interrupt-status
// register (NOTIF/ERROR INTERNAL_INTR_R, which is hwset on the event and latches
// independent of the *_intr_en gates) into cptra_intr_rcv and W1C-clears it,
// exactly as the real ISRs do. The W1C is what makes repeated operations on the
// same block work (otherwise a stale "done" bit would exit the next wait early).
#include "caliptra_defines.h"
#include "caliptra_reg.h"
#include "caliptra_isr.h"      // caliptra_intr_received_s + extern cptra_intr_rcv
#include "riscv_hw_if.h"       // lsu_read_32 / lsu_write_32

extern volatile caliptra_intr_received_s cptra_intr_rcv;

void init_interrupts(void) {}

// Reflect one block's NOTIF and ERROR interrupt-status registers into the
// matching cptra_intr_rcv fields, clearing the hardware bits (write-1-to-clear).
#define FB_REFLECT(NOTIF_FIELD, ERROR_FIELD, NOTIF_REG, ERROR_REG)            \
    do {                                                                     \
        uint32_t _n = lsu_read_32(NOTIF_REG);                                \
        if (_n) { lsu_write_32((NOTIF_REG), _n); cptra_intr_rcv.NOTIF_FIELD |= _n; } \
        uint32_t _e = lsu_read_32(ERROR_REG);                                \
        if (_e) { lsu_write_32((ERROR_REG), _e); cptra_intr_rcv.ERROR_FIELD |= _e; } \
    } while (0)

void asm_wfi(void) {
    FB_REFLECT(sha256_notif, sha256_error,
               CLP_SHA256_REG_INTR_BLOCK_RF_NOTIF_INTERNAL_INTR_R,
               CLP_SHA256_REG_INTR_BLOCK_RF_ERROR_INTERNAL_INTR_R);
    FB_REFLECT(sha512_notif, sha512_error,
               CLP_SHA512_REG_INTR_BLOCK_RF_NOTIF_INTERNAL_INTR_R,
               CLP_SHA512_REG_INTR_BLOCK_RF_ERROR_INTERNAL_INTR_R);
    FB_REFLECT(hmac_notif, hmac_error,
               CLP_HMAC_REG_INTR_BLOCK_RF_NOTIF_INTERNAL_INTR_R,
               CLP_HMAC_REG_INTR_BLOCK_RF_ERROR_INTERNAL_INTR_R);
    FB_REFLECT(ecc_notif, ecc_error,
               CLP_ECC_REG_INTR_BLOCK_RF_NOTIF_INTERNAL_INTR_R,
               CLP_ECC_REG_INTR_BLOCK_RF_ERROR_INTERNAL_INTR_R);
    FB_REFLECT(abr_notif, abr_error,   // ML-DSA / ML-KEM
               CLP_ABR_REG_INTR_BLOCK_RF_NOTIF_INTERNAL_INTR_R,
               CLP_ABR_REG_INTR_BLOCK_RF_ERROR_INTERNAL_INTR_R);
}
