// SPDX-License-Identifier: Apache-2.0
// FireBridge stub: el2_veer_wrapper with all outputs tied to 0.
// Used when FB_HAL=1 (CALIPTRA_FB_AHB) to avoid parsing the full VeeR RTL.
// VeeR is held in reset in FB mode, so all outputs can safely be 0.
// No parameters needed: caliptra_top.sv instantiates without explicit params,
// and all outputs are tied to '0 so pt.* fields are never referenced.

module el2_veer_wrapper
import el2_pkg::*;
(
   input logic                             clk,
   input logic                             rst_l,
   input logic                             dbg_rst_l,
   input logic [31:1]                      rst_vec,
   input logic                             nmi_int,
   input logic [31:1]                      nmi_vec,

   output logic [31:0]                     trace_rv_i_insn_ip,
   output logic [31:0]                     trace_rv_i_address_ip,
   output logic                            trace_rv_i_valid_ip,
   output logic                            trace_rv_i_exception_ip,
   output logic [4:0]                      trace_rv_i_ecause_ip,
   output logic                            trace_rv_i_interrupt_ip,
   output logic [31:0]                     trace_rv_i_tval_ip,

`ifdef RV_BUILD_AXI4
   output logic                            lsu_axi_awvalid,
   input  logic                            lsu_axi_awready,
   output logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_awid,
   output logic [31:0]                     lsu_axi_awaddr,
   output logic [3:0]                      lsu_axi_awregion,
   output logic [7:0]                      lsu_axi_awlen,
   output logic [2:0]                      lsu_axi_awsize,
   output logic [1:0]                      lsu_axi_awburst,
   output logic                            lsu_axi_awlock,
   output logic [3:0]                      lsu_axi_awcache,
   output logic [2:0]                      lsu_axi_awprot,
   output logic [3:0]                      lsu_axi_awqos,

   output logic                            lsu_axi_wvalid,
   input  logic                            lsu_axi_wready,
   output logic [63:0]                     lsu_axi_wdata,
   output logic [7:0]                      lsu_axi_wstrb,
   output logic                            lsu_axi_wlast,

   input  logic                            lsu_axi_bvalid,
   output logic                            lsu_axi_bready,
   input  logic [1:0]                      lsu_axi_bresp,
   input  logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_bid,

   output logic                            lsu_axi_arvalid,
   input  logic                            lsu_axi_arready,
   output logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_arid,
   output logic [31:0]                     lsu_axi_araddr,
   output logic [3:0]                      lsu_axi_arregion,
   output logic [7:0]                      lsu_axi_arlen,
   output logic [2:0]                      lsu_axi_arsize,
   output logic [1:0]                      lsu_axi_arburst,
   output logic                            lsu_axi_arlock,
   output logic [3:0]                      lsu_axi_arcache,
   output logic [2:0]                      lsu_axi_arprot,
   output logic [3:0]                      lsu_axi_arqos,

   input  logic                            lsu_axi_rvalid,
   output logic                            lsu_axi_rready,
   input  logic [pt.LSU_BUS_TAG-1:0]       lsu_axi_rid,
   input  logic [63:0]                     lsu_axi_rdata,
   input  logic [1:0]                      lsu_axi_rresp,
   input  logic                            lsu_axi_rlast,

   output logic                            ifu_axi_awvalid,
   input  logic                            ifu_axi_awready,
   output logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_awid,
   output logic [31:0]                     ifu_axi_awaddr,
   output logic [3:0]                      ifu_axi_awregion,
   output logic [7:0]                      ifu_axi_awlen,
   output logic [2:0]                      ifu_axi_awsize,
   output logic [1:0]                      ifu_axi_awburst,
   output logic                            ifu_axi_awlock,
   output logic [3:0]                      ifu_axi_awcache,
   output logic [2:0]                      ifu_axi_awprot,
   output logic [3:0]                      ifu_axi_awqos,

   output logic                            ifu_axi_wvalid,
   input  logic                            ifu_axi_wready,
   output logic [63:0]                     ifu_axi_wdata,
   output logic [7:0]                      ifu_axi_wstrb,
   output logic                            ifu_axi_wlast,

   input  logic                            ifu_axi_bvalid,
   output logic                            ifu_axi_bready,
   input  logic [1:0]                      ifu_axi_bresp,
   input  logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_bid,

   output logic                            ifu_axi_arvalid,
   input  logic                            ifu_axi_arready,
   output logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_arid,
   output logic [31:0]                     ifu_axi_araddr,
   output logic [3:0]                      ifu_axi_arregion,
   output logic [7:0]                      ifu_axi_arlen,
   output logic [2:0]                      ifu_axi_arsize,
   output logic [1:0]                      ifu_axi_arburst,
   output logic                            ifu_axi_arlock,
   output logic [3:0]                      ifu_axi_arcache,
   output logic [2:0]                      ifu_axi_arprot,
   output logic [3:0]                      ifu_axi_arqos,

   input  logic                            ifu_axi_rvalid,
   output logic                            ifu_axi_rready,
   input  logic [pt.IFU_BUS_TAG-1:0]       ifu_axi_rid,
   input  logic [63:0]                     ifu_axi_rdata,
   input  logic [1:0]                      ifu_axi_rresp,
   input  logic                            ifu_axi_rlast,

   output logic                            sb_axi_awvalid,
   input  logic                            sb_axi_awready,
   output logic [pt.SB_BUS_TAG-1:0]        sb_axi_awid,
   output logic [31:0]                     sb_axi_awaddr,
   output logic [3:0]                      sb_axi_awregion,
   output logic [7:0]                      sb_axi_awlen,
   output logic [2:0]                      sb_axi_awsize,
   output logic [1:0]                      sb_axi_awburst,
   output logic                            sb_axi_awlock,
   output logic [3:0]                      sb_axi_awcache,
   output logic [2:0]                      sb_axi_awprot,
   output logic [3:0]                      sb_axi_awqos,

   output logic                            sb_axi_wvalid,
   input  logic                            sb_axi_wready,
   output logic [63:0]                     sb_axi_wdata,
   output logic [7:0]                      sb_axi_wstrb,
   output logic                            sb_axi_wlast,

   input  logic                            sb_axi_bvalid,
   output logic                            sb_axi_bready,
   input  logic [1:0]                      sb_axi_bresp,
   input  logic [pt.SB_BUS_TAG-1:0]        sb_axi_bid,

   output logic                            sb_axi_arvalid,
   input  logic                            sb_axi_arready,
   output logic [pt.SB_BUS_TAG-1:0]        sb_axi_arid,
   output logic [31:0]                     sb_axi_araddr,
   output logic [3:0]                      sb_axi_arregion,
   output logic [7:0]                      sb_axi_arlen,
   output logic [2:0]                      sb_axi_arsize,
   output logic [1:0]                      sb_axi_arburst,
   output logic                            sb_axi_arlock,
   output logic [3:0]                      sb_axi_arcache,
   output logic [2:0]                      sb_axi_arprot,
   output logic [3:0]                      sb_axi_arqos,

   input  logic                            sb_axi_rvalid,
   output logic                            sb_axi_rready,
   input  logic [pt.SB_BUS_TAG-1:0]        sb_axi_rid,
   input  logic [63:0]                     sb_axi_rdata,
   input  logic [1:0]                      sb_axi_rresp,
   input  logic                            sb_axi_rlast,

   input  logic                            dma_axi_awvalid,
   output logic                            dma_axi_awready,
   input  logic [pt.DMA_BUS_TAG-1:0]       dma_axi_awid,
   input  logic [31:0]                     dma_axi_awaddr,
   input  logic [2:0]                      dma_axi_awsize,
   input  logic [2:0]                      dma_axi_awprot,
   input  logic [7:0]                      dma_axi_awlen,
   input  logic [1:0]                      dma_axi_awburst,

   input  logic                            dma_axi_wvalid,
   output logic                            dma_axi_wready,
   input  logic [63:0]                     dma_axi_wdata,
   input  logic [7:0]                      dma_axi_wstrb,

   output logic                            dma_axi_bvalid,
   input  logic                            dma_axi_bready,
   output logic [1:0]                      dma_axi_bresp,
   output logic [pt.DMA_BUS_TAG-1:0]       dma_axi_bid,

   input  logic                            dma_axi_arvalid,
   output logic                            dma_axi_arready,
   input  logic [pt.DMA_BUS_TAG-1:0]       dma_axi_arid,
   input  logic [31:0]                     dma_axi_araddr,
   input  logic [2:0]                      dma_axi_arsize,
   input  logic [2:0]                      dma_axi_arprot,
   input  logic [7:0]                      dma_axi_arlen,
   input  logic [1:0]                      dma_axi_arburst,

   output logic                            dma_axi_rvalid,
   input  logic                            dma_axi_rready,
   output logic [pt.DMA_BUS_TAG-1:0]       dma_axi_rid,
   output logic [63:0]                     dma_axi_rdata,
   output logic [1:0]                      dma_axi_rresp,
   output logic                            dma_axi_rlast,
`endif

   // AHB bus interface (unconditional — stub is AHB-only)
   output logic [31:0]                     haddr,
   output logic [2:0]                      hburst,
   output logic                            hmastlock,
   output logic [3:0]                      hprot,
   output logic [2:0]                      hsize,
   output logic [1:0]                      htrans,
   output logic                            hwrite,

   input logic [63:0]                      hrdata,
   input logic                             hready,
   input logic                             hresp,

   output logic [31:0]                     sb_haddr,
   output logic [2:0]                      sb_hburst,
   output logic                            sb_hmastlock,
   output logic [3:0]                      sb_hprot,
   output logic [2:0]                      sb_hsize,
   output logic [1:0]                      sb_htrans,
   output logic                            sb_hwrite,
   output logic [63:0]                     sb_hwdata,

   input logic [63:0]                      sb_hrdata,
   input logic                             sb_hready,
   input logic                             sb_hresp,

   output logic [31:0]                     lsu_haddr,
   output logic [2:0]                      lsu_hburst,
   output logic                            lsu_hmastlock,
   output logic [3:0]                      lsu_hprot,
   output logic [2:0]                      lsu_hsize,
   output logic [1:0]                      lsu_htrans,
   output logic                            lsu_hwrite,
   output logic [63:0]                     lsu_hwdata,

   input logic [63:0]                      lsu_hrdata,
   input logic                             lsu_hready,
   input logic                             lsu_hresp,

   input logic [31:0]                      dma_haddr,
   input logic [2:0]                       dma_hburst,
   input logic                             dma_hmastlock,
   input logic [3:0]                       dma_hprot,
   input logic [2:0]                       dma_hsize,
   input logic [1:0]                       dma_htrans,
   input logic                             dma_hwrite,
   input logic [63:0]                      dma_hwdata,

   output logic [63:0]                     dma_hrdata,
   output logic                            dma_hreadyout,
   output logic                            dma_hresp,

   input logic                             dma_hsel,
   input logic                             dma_hreadyin,

   input logic                             timer_int,
   input logic                             soft_int,
   input logic [30:0]                      extintsrc_req,  // `RV_PIC_TOTAL_INT=31

   output logic                            iccm_ecc_single_error,
   output logic                            iccm_ecc_double_error,
   output logic                            dccm_ecc_single_error,
   output logic                            dccm_ecc_double_error,

   output logic [3:0]                      dec_tlu_perfcnt0,
   output logic [3:0]                      dec_tlu_perfcnt1,
   output logic [3:0]                      dec_tlu_perfcnt2,
   output logic [3:0]                      dec_tlu_perfcnt3,

   el2_mem_if.veer_icache_src              el2_icache_export,

   input logic                             lsu_bus_clk_en,
   input logic                             ifu_bus_clk_en,
   input logic                             dbg_bus_clk_en,
   input logic                             dma_bus_clk_en,

   input logic                             jtag_tck,
   input logic                             jtag_tms,
   input logic                             jtag_tdi,
   input logic                             jtag_trst_n,
   output logic                            jtag_tdo,
   output logic                            jtag_tdoEn,

   input logic [31:4]                      core_id,

   el2_mem_if.veer_sram_src                el2_mem_export,

   input logic                             mpc_debug_halt_req,
   input logic                             mpc_debug_run_req,
   input logic                             mpc_reset_run_req,
   output logic                            mpc_debug_halt_ack,
   output logic                            mpc_debug_run_ack,
   output logic                            debug_brkpt_status,

   input logic                             i_cpu_halt_req,
   output logic                            o_cpu_halt_ack,
   output logic                            o_cpu_halt_status,
   output logic                            o_debug_mode_status,
   input logic                             i_cpu_run_req,
   output logic                            o_cpu_run_ack,

   input logic                             scan_mode,
   input logic                             mbist_mode,

   input logic                             dmi_core_enable,
   input logic                             dmi_uncore_enable,
   output logic                            dmi_uncore_en,
   output logic                            dmi_uncore_wr_en,
   output logic [6:0]                      dmi_uncore_addr,
   output logic [31:0]                     dmi_uncore_wdata,
   input logic  [31:0]                     dmi_uncore_rdata,
   output logic                            dmi_active
);

  // All outputs tied to 0: VeeR is held in reset in CALIPTRA_FB_AHB mode
  assign trace_rv_i_insn_ip     = '0;
  assign trace_rv_i_address_ip  = '0;
  assign trace_rv_i_valid_ip    = '0;
  assign trace_rv_i_exception_ip = '0;
  assign trace_rv_i_ecause_ip   = '0;
  assign trace_rv_i_interrupt_ip = '0;
  assign trace_rv_i_tval_ip     = '0;

`ifdef RV_BUILD_AXI4
  assign lsu_axi_awvalid = '0;  assign lsu_axi_awid = '0;   assign lsu_axi_awaddr = '0;
  assign lsu_axi_awregion = '0; assign lsu_axi_awlen = '0;   assign lsu_axi_awsize = '0;
  assign lsu_axi_awburst = '0;  assign lsu_axi_awlock = '0;  assign lsu_axi_awcache = '0;
  assign lsu_axi_awprot = '0;   assign lsu_axi_awqos = '0;
  assign lsu_axi_wvalid = '0;   assign lsu_axi_wdata = '0;   assign lsu_axi_wstrb = '0;
  assign lsu_axi_wlast = '0;    assign lsu_axi_bready = '0;
  assign lsu_axi_arvalid = '0;  assign lsu_axi_arid = '0;    assign lsu_axi_araddr = '0;
  assign lsu_axi_arregion = '0; assign lsu_axi_arlen = '0;   assign lsu_axi_arsize = '0;
  assign lsu_axi_arburst = '0;  assign lsu_axi_arlock = '0;  assign lsu_axi_arcache = '0;
  assign lsu_axi_arprot = '0;   assign lsu_axi_arqos = '0;   assign lsu_axi_rready = '0;
  assign ifu_axi_awvalid = '0;  assign ifu_axi_awid = '0;    assign ifu_axi_awaddr = '0;
  assign ifu_axi_awregion = '0; assign ifu_axi_awlen = '0;   assign ifu_axi_awsize = '0;
  assign ifu_axi_awburst = '0;  assign ifu_axi_awlock = '0;  assign ifu_axi_awcache = '0;
  assign ifu_axi_awprot = '0;   assign ifu_axi_awqos = '0;
  assign ifu_axi_wvalid = '0;   assign ifu_axi_wdata = '0;   assign ifu_axi_wstrb = '0;
  assign ifu_axi_wlast = '0;    assign ifu_axi_bready = '0;
  assign ifu_axi_arvalid = '0;  assign ifu_axi_arid = '0;    assign ifu_axi_araddr = '0;
  assign ifu_axi_arregion = '0; assign ifu_axi_arlen = '0;   assign ifu_axi_arsize = '0;
  assign ifu_axi_arburst = '0;  assign ifu_axi_arlock = '0;  assign ifu_axi_arcache = '0;
  assign ifu_axi_arprot = '0;   assign ifu_axi_arqos = '0;   assign ifu_axi_rready = '0;
  assign sb_axi_awvalid = '0;   assign sb_axi_awid = '0;     assign sb_axi_awaddr = '0;
  assign sb_axi_awregion = '0;  assign sb_axi_awlen = '0;    assign sb_axi_awsize = '0;
  assign sb_axi_awburst = '0;   assign sb_axi_awlock = '0;   assign sb_axi_awcache = '0;
  assign sb_axi_awprot = '0;    assign sb_axi_awqos = '0;
  assign sb_axi_wvalid = '0;    assign sb_axi_wdata = '0;    assign sb_axi_wstrb = '0;
  assign sb_axi_wlast = '0;     assign sb_axi_bready = '0;
  assign sb_axi_arvalid = '0;   assign sb_axi_arid = '0;     assign sb_axi_araddr = '0;
  assign sb_axi_arregion = '0;  assign sb_axi_arlen = '0;    assign sb_axi_arsize = '0;
  assign sb_axi_arburst = '0;   assign sb_axi_arlock = '0;   assign sb_axi_arcache = '0;
  assign sb_axi_arprot = '0;    assign sb_axi_arqos = '0;    assign sb_axi_rready = '0;
  assign dma_axi_awready = '0;  assign dma_axi_wready = '0;
  assign dma_axi_bvalid = '0;   assign dma_axi_bresp = '0;   assign dma_axi_bid = '0;
  assign dma_axi_arready = '0;
  assign dma_axi_rvalid = '0;   assign dma_axi_rid = '0;     assign dma_axi_rdata = '0;
  assign dma_axi_rresp = '0;    assign dma_axi_rlast = '0;
`endif

  // AHB outputs
  assign haddr     = '0;  assign hburst    = '0;  assign hmastlock = '0;
  assign hprot     = '0;  assign hsize     = '0;  assign htrans    = '0;
  assign hwrite    = '0;
  assign sb_haddr  = '0;  assign sb_hburst = '0;  assign sb_hmastlock = '0;
  assign sb_hprot  = '0;  assign sb_hsize  = '0;  assign sb_htrans = '0;
  assign sb_hwrite = '0;  assign sb_hwdata = '0;
  assign lsu_haddr  = '0; assign lsu_hburst = '0; assign lsu_hmastlock = '0;
  assign lsu_hprot  = '0; assign lsu_hsize  = '0; assign lsu_htrans = '0;
  assign lsu_hwrite = '0; assign lsu_hwdata = '0;
  assign dma_hrdata    = '0;
  assign dma_hreadyout = '0;
  assign dma_hresp     = '0;

  assign iccm_ecc_single_error = '0;
  assign iccm_ecc_double_error = '0;
  assign dccm_ecc_single_error = '0;
  assign dccm_ecc_double_error = '0;
  assign dec_tlu_perfcnt0 = '0;
  assign dec_tlu_perfcnt1 = '0;
  assign dec_tlu_perfcnt2 = '0;
  assign dec_tlu_perfcnt3 = '0;
  assign jtag_tdo    = '0;
  assign jtag_tdoEn  = '0;
  assign mpc_debug_halt_ack  = '0;
  assign mpc_debug_run_ack   = '0;
  assign debug_brkpt_status  = '0;
  assign o_cpu_halt_ack      = '0;
  assign o_cpu_halt_status   = '0;
  assign o_debug_mode_status = '0;
  assign o_cpu_run_ack       = '0;
  assign dmi_uncore_en    = '0;
  assign dmi_uncore_wr_en = '0;
  assign dmi_uncore_addr  = '0;
  assign dmi_uncore_wdata = '0;
  assign dmi_active       = '0;

  // el2_mem_export interface outputs (veer_sram_src modport)
  // Clock ICCM/DCCM from the system clock (not from VeeR's gated clock) so
  // the SRAM remains functional for tests like smoke_test_sram_ecc that inject
  // ECC errors into the VeeR SRAM banks via the TB services interface.
  assign el2_mem_export.clk             = clk;
  assign el2_mem_export.iccm_clken      = '0;
  assign el2_mem_export.iccm_wren_bank  = '0;
  assign el2_mem_export.iccm_addr_bank  = '0;
  assign el2_mem_export.iccm_bank_wr_data = '0;
  assign el2_mem_export.iccm_bank_wr_ecc  = '0;
  assign el2_mem_export.dccm_clken      = '0;
  assign el2_mem_export.dccm_wren_bank  = '0;
  assign el2_mem_export.dccm_addr_bank  = '0;
  assign el2_mem_export.dccm_wr_data_bank = '0;
  assign el2_mem_export.dccm_wr_ecc_bank  = '0;

  // el2_icache_export interface outputs (veer_icache_src modport)
  assign el2_icache_export.ic_b_sb_wren           = '0;
  assign el2_icache_export.ic_b_sb_bit_en_vec      = '0;
  assign el2_icache_export.ic_sb_wr_data           = '0;
  assign el2_icache_export.ic_rw_addr_bank_q       = '0;
  assign el2_icache_export.ic_bank_way_clken_final = '0;
  assign el2_icache_export.ic_bank_way_clken_final_up = '0;
  assign el2_icache_export.ic_tag_clken_final      = '0;
  assign el2_icache_export.ic_tag_wren_q           = '0;
  assign el2_icache_export.ic_tag_wren_biten_vec   = '0;
  assign el2_icache_export.ic_tag_wr_data          = '0;
  assign el2_icache_export.ic_rw_addr_q            = '0;

endmodule
