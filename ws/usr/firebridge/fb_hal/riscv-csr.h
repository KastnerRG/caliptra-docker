// FireBridge stub for riscv-csr.h — host (x86) compilation.
// The original header (libs/caliptra_isr/riscv-csr.h) uses __riscv_xlen and
// inline CSR assembly that will not compile on x86. None of the Caliptra
// test .c files that #include riscv-csr.h actually CALL any CSR accessor
// function under FireBridge, so providing just the type aliases is enough.
#ifndef RISCV_CSR_H
#define RISCV_CSR_H

#include <stdint.h>

// Caliptra is always rv32; treat as 32-bit on the host stub.
typedef uint32_t uint_xlen_t;
typedef uint32_t uint_csr32_t;
typedef uint32_t uint_csr64_t;

#endif /* RISCV_CSR_H */
