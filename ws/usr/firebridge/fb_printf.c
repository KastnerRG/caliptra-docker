// FireBridge host-side replacement for the Caliptra test-suite printf.c.
// Compiled instead of the upstream printf.c under the FireBridge build. The
// upstream firmware's printf/putchar/puts are renamed to fw_printf/fw_putchar/
// fw_puts (so they don't clobber the libc symbols Verilator's runtime uses);
// this file provides those fw_* definitions, routing output to the host via
// fb_putc() (implemented in the harness). This file itself is compiled WITHOUT
// the renames so it can use the host C library normally.
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif
void fb_putc(int c);  // harness-provided sink (e.g. fputc to stderr)
#ifdef __cplusplus
}
#endif

static void emit(const char* s) {
    for (; *s; ++s) fb_putc((unsigned char)*s);
}

int fw_putchar(int c) { fb_putc(c); return c; }

int fw_puts(const char* s) { emit(s); fb_putc('\n'); return 1; }

int fw_printf(const char* format, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, format);
    int n = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    emit(buf);
    return n;
}

// Some firmware reads mcycle for perf counters; not meaningful under FireBridge.
uint64_t get_mcycle(void) { return 0; }
