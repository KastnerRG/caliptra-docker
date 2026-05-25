#ifndef FB_FW_WRAP_H
#define FB_FW_WRAP_H

#ifndef RISCV
  #include <assert.h>
  #include <stdlib.h>
#endif
#include <limits.h>
#include <stdint.h>

typedef int8_t   i8 ;
typedef int16_t  i16;
typedef int32_t  i32;
typedef int64_t  i64;
typedef uint8_t  u8 ;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef float    f32;
typedef double   f64;

#ifdef __cplusplus
  #define EXT_C "C"
  #define restrict __restrict__
#else
  #define EXT_C
#endif

#ifndef REG_WIDTH
  #define REG_WIDTH 32
#endif

#if (REG_WIDTH == 32)
  typedef volatile u32 fb_reg_t;
#elif (REG_WIDTH == 64)
  typedef volatile u64 fb_reg_t;
#else
  #error "REG_WIDTH must be 32 or 64"
#endif

#ifdef FB_FW_WRAP_EXTERNAL_DPI
extern EXT_C void *fb_get_mem_p(void);
#else
extern EXT_C void *fb_get_mem_p(){
  return &mem;
}
#endif

#ifdef SIM
  #define XDEBUG
  #include <stdio.h>
  #include <stdbool.h>

  extern EXT_C void fb_task_write_reg(u64 addr, u64 data);
  extern EXT_C void fb_task_read_reg(u64 addr);
  extern EXT_C u64  fb_fn_read_reg(void);

  static inline fb_reg_t fb_read_reg(fb_reg_t *addr) {
    fb_task_read_reg((u64)(uintptr_t)addr);
    return (fb_reg_t)fb_fn_read_reg();
  }

  static inline void fb_write_reg(fb_reg_t *addr, fb_reg_t data) {
    fb_task_write_reg((u64)(uintptr_t)addr, (u64)data);
  }

  #ifndef FB_CUSTOM_FLUSH_CACHE
  static inline void flush_cache(void *addr, uint32_t bytes) { (void)addr; (void)bytes; }
  #endif

#elif defined(AHB_SIM)
  #include <stdio.h>
  #include <stdbool.h>
  #include <stdlib.h>

  // AHB bus is driven from C: SV exposes signal accessors as DPI export
  // *functions* (tasks have a Verilator 5.044 codegen bug, see fb_ahb_vip.sv).
  extern EXT_C void fb_ahb_drive(u8 hsel, u32 haddr, u32 hwdata,
                                 u8 hwrite, u8 hsize, u8 htrans, u8 hready);
  extern EXT_C u8   fb_ahb_hreadyout(void);
  extern EXT_C u8   fb_ahb_hresp(void);
  extern EXT_C u32  fb_ahb_hrdata(void);
  extern EXT_C void at_posedge_clk(void);
  extern EXT_C void step_time_veri(void);

  #define FB_AHB_HSIZE_WORD    ((u8)2)
  #define FB_AHB_HTRANS_IDLE   ((u8)0)
  #define FB_AHB_HTRANS_NONSEQ ((u8)2)
  #ifndef FB_AHB_TIMEOUT
    #define FB_AHB_TIMEOUT 200000
  #endif

  static inline void fb_ahb_idle(void) {
    fb_ahb_drive(0, 0, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
  }

  static inline void fb_ahb_wait_ready(const char *op, u32 addr) {
    int i;
    for (i = 0; i < FB_AHB_TIMEOUT; i++) {
      if (fb_ahb_hreadyout()) break;
      step_time_veri();
    }
    if (i >= FB_AHB_TIMEOUT) {
      fprintf(stderr, "FB_AHB: timeout waiting HREADYOUT during %s addr=0x%08x\n", op, addr);
      abort();
    }
    if (fb_ahb_hresp()) {
      fprintf(stderr, "FB_AHB: HRESP error during %s addr=0x%08x\n", op, addr);
      abort();
    }
  }

  static inline void fb_write_reg(fb_reg_t *addr_ptr, fb_reg_t data) {
    u32 addr = (u32)(uintptr_t)addr_ptr;
    // Address phase
    at_posedge_clk(); step_time_veri();
    fb_ahb_drive(1, addr, 0, 1, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_NONSEQ, 1);
    // Data phase
    at_posedge_clk(); step_time_veri();
    fb_ahb_drive(0, 0, (u32)data, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
    fb_ahb_wait_ready("write", addr);
    at_posedge_clk(); step_time_veri();
    fb_ahb_idle();
  }

  static inline fb_reg_t fb_read_reg(fb_reg_t *addr_ptr) {
    u32 addr = (u32)(uintptr_t)addr_ptr;
    // Address phase
    at_posedge_clk(); step_time_veri();
    fb_ahb_drive(1, addr, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_NONSEQ, 1);
    // Data phase
    at_posedge_clk(); step_time_veri();
    fb_ahb_drive(0, 0, 0, 0, FB_AHB_HSIZE_WORD, FB_AHB_HTRANS_IDLE, 1);
    fb_ahb_wait_ready("read", addr);
    step_time_veri();
    fb_reg_t result = (fb_reg_t)fb_ahb_hrdata();
    at_posedge_clk(); step_time_veri();
    fb_ahb_idle();
    return result;
  }

  #ifndef FB_CUSTOM_FLUSH_CACHE
  static inline void flush_cache(void *addr, uint32_t bytes) { (void)addr; (void)bytes; }
  #endif

#else
  #define sim_fprintf(...)

  static inline fb_reg_t fb_read_reg(fb_reg_t *addr) {
    return *addr;
  }

  static inline void fb_write_reg(fb_reg_t *addr, fb_reg_t data) {
    *addr = data;
  }

  #ifndef FB_CUSTOM_FLUSH_CACHE
  static inline void flush_cache(void *addr, uint32_t bytes) { (void)addr; (void)bytes; }
  #endif
#endif

#ifdef XDEBUG
  #define debug_printf printf
  #define assert_printf(v1, op, v2, optional_debug_info,...) ((v1  op v2) || (debug_printf("ASSERT FAILED: \n CONDITION: "), debug_printf("( " #v1 " " #op " " #v2 " )"), debug_printf(", VALUES: ( %d %s %d ), ", v1, #op, v2), debug_printf("DEBUG_INFO: " optional_debug_info), debug_printf(" " __VA_ARGS__), debug_printf("\n\n"), assert(v1 op v2), 0))
#else
  #define assert_printf(...)
  #define debug_printf(...)
#endif

// Rest of the helper functions used in simulation.
#ifdef SIM

#define FB_SIM_DDR_BASE 0x20000000u

static inline u32 fb_shorten_ptr(void* addr, void* p_mem){
  u64 offset = (u64)(uintptr_t)addr - (u64)(uintptr_t)p_mem;
  return (u32)offset + (u32)FB_SIM_DDR_BASE;
}

static inline u64 fb_widen_ptr(u32 addr, void* p_mem){
  return (u64)addr - (u64)FB_SIM_DDR_BASE + (u64)(uintptr_t)p_mem;
}

#ifdef FB_FW_WRAP_EXTERNAL_DPI
extern EXT_C u8   fb_c_read_ddr8_addr32   (u32 addr_32, void* p_mem);
extern EXT_C void fb_c_write_ddr8_addr32  (u32 addr_32, u8  data, void* p_mem);
extern EXT_C u32  fb_c_read_ddr32_addr32  (u32 addr_32, void* p_mem);
extern EXT_C void fb_c_write_ddr32_addr32 (u32 addr_32, u32 data, u8 strb, void* p_mem);
#else
extern EXT_C u8 fb_c_read_ddr8_addr32 (u32 addr_32, void* p_mem){
  u64 addr = fb_widen_ptr(addr_32, p_mem);
  u8 val = *(u8*restrict)(uintptr_t)addr;
  return val;
}

extern EXT_C void fb_c_write_ddr8_addr32 (u32 addr_32, u8 data, void* p_mem){
  u64 addr = fb_widen_ptr(addr_32, p_mem);
  *(u8*restrict)(uintptr_t)addr = data;
}

extern EXT_C u32 fb_c_read_ddr32_addr32 (u32 addr_32, void* p_mem){
  u64 addr = fb_widen_ptr(addr_32, p_mem);
  return *(u32*restrict)(uintptr_t)addr;
}

extern EXT_C void fb_c_write_ddr32_addr32 (u32 addr_32, u32 data, u8 strb, void* p_mem){
  u8*restrict ptr = (u8*restrict)(uintptr_t)fb_widen_ptr(addr_32, p_mem);
  if (strb == 0xF) { *(u32*restrict)ptr = data; return; }
  for (int i = 0; i < 4; i++)
    if ((strb >> i) & 1) ptr[i] = (u8)(data >> (i*8));
}
#endif

#else

static inline u32 fb_shorten_ptr (void* addr, void* p_mem){
  return (u32)((uintptr_t)addr);
}
#endif

#endif
