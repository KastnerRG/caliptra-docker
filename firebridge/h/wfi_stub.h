// FireBridge stub: make x86 assembler accept bare `wfi` inline asm.
// Some upstream tests use __asm__ volatile ("wfi") directly instead of
// calling asm_wfi().  The C preprocessor cannot intercept the string content
// of inline asm, so we inject a GAS .macro definition at the top of every
// FB firmware object.  When GAS sees the `wfi` mnemonic it expands the macro
// to `call asm_wfi`, which is our ISR-reflector (isr.c) — semantically
// correct: asm_wfi() reads the interrupt-status AHB regs and updates
// cptra_intr_rcv, exactly what a real wfi would trigger via the PLIC.
#ifndef WFI_STUB_H
#define WFI_STUB_H

__asm__(".macro wfi\n\tcall asm_wfi\n.endm\n");

#endif /* WFI_STUB_H */
