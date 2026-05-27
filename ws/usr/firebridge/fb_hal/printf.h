// FireBridge HAL replacement for the Caliptra test-suite printf.h.
// Keeps the same public surface (enum printf_verbosity, verbosity_g, printf/
// putchar/puts, VPRINTF, SEND_STDOUT_CTRL) so unmodified firmware compiles, but
// routes output to the host and turns the simulation-control codes (0xff pass,
// 0x1 fail) into harness calls instead of MMIO writes to *stdout.
#ifndef PRINTF_H
#define PRINTF_H

enum printf_verbosity {
    FATAL   = 0,
    ERROR   = 1,
    WARNING = 2,
    LOW     = 3,
    MEDIUM  = 4,
    HIGH    = 5,
    ALL     = 6
};
extern enum printf_verbosity verbosity_g;

int putchar(int c);
int puts(const char* s);
int printf(const char* format, ...);

// Provided by the harness: terminate the current test with the given control
// code (the firmware passes 0xff for pass, 0x1 for fail, 0xfb/0xfc are ISR
// trace markers). Does not return for terminal codes.
#ifdef __cplusplus
extern "C" {
#endif
void fb_stdout_ctrl(int ctrl);
#ifdef __cplusplus
}
#endif

#define VPRINTF(VERBOSITY, format, ...)                          \
    do {                                                         \
        if ((VERBOSITY) <= verbosity_g)                          \
            printf(format, ##__VA_ARGS__);                       \
    } while (0)

#define SEND_STDOUT_CTRL(ctrl) fb_stdout_ctrl((int)(unsigned char)(ctrl))

#endif // PRINTF_H
