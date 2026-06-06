// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
`default_nettype none

`include "common_defines.sv"
`include "config_defines.svh"
`include "caliptra_reg_defines.svh"
`include "caliptra_reg_field_defines.svh"
`include "caliptra_macros.svh"

`ifndef VERILATOR
module caliptra_top_tb;
`else
module caliptra_top_tb (
    input bit core_clk,
    input bit rst_l
    );
`endif

    import axi_pkg::*;
    import kv_defines_pkg::*;
    import soc_ifc_pkg::*;
    import caliptra_top_tb_pkg::*;

`ifndef VERILATOR
    // Time formatting for %t in display tasks
    // -9 = ns units
    // 3  = 3 bits of precision (to the ps)
    // "ns" = nanosecond suffix for output time values
    // 15 = 15 bits minimum field width
    initial $timeformat(-9, 3, " ns", 15); // up to 99ms representable in this width
`endif

`ifndef VERILATOR
    bit                         core_clk;
`endif

    int                         cycleCnt;


    logic [15:0] strap_ss_key_release_key_size;
    logic [63:0] strap_ss_key_release_base_addr;

    logic                       cptra_pwrgood;
    logic                       cptra_rst_b;
    logic                       BootFSM_BrkPoint;
    logic                       scan_mode;

    logic                       recovery_data_avail;

    logic [`CLP_OBF_KEY_DWORDS-1:0][31:0]          cptra_obf_key;
    
    logic [`CLP_CSR_HMAC_KEY_DWORDS-1:0][31:0]     cptra_csr_hmac_key;

    logic [0:`CLP_OBF_UDS_DWORDS-1][31:0]          cptra_uds_rand;
    logic [0:`CLP_OBF_FE_DWORDS-1][31:0]           cptra_fe_rand;
    logic [0:OCP_LOCK_HEK_NUM_DWORDS-1][31:0]      cptra_hek_rand;
    logic [0:`CLP_OBF_KEY_DWORDS-1][31:0]          cptra_obf_key_tb;

    //jtag interface
    logic                       jtag_tck;    // JTAG clk
    logic                       jtag_tms;    // JTAG TMS
    logic                       jtag_tdi;    // JTAG tdi
    logic                       jtag_trst_n; // JTAG Reset
    logic                       jtag_tdo;    // JTAG TDO
    logic                       jtag_tdoEn;  // JTAG TDO enable

    logic                       axi_error_inj_en;

    // AXI Interface
    axi_if #(
        .AW(`CALIPTRA_SLAVE_ADDR_WIDTH(`CALIPTRA_SLAVE_SEL_SOC_IFC)),
        .DW(`CALIPTRA_AXI_DATA_WIDTH),
        .IW(`CALIPTRA_AXI_ID_WIDTH),
        .UW(`CALIPTRA_AXI_USER_WIDTH)
    ) m_axi_bfm_if (.clk(core_clk), .rst_n(cptra_rst_b));
    axi_if #(
        .AW(`CALIPTRA_AXI_DMA_ADDR_WIDTH),
        .DW(CPTRA_AXI_DMA_DATA_WIDTH),
        .IW(CPTRA_AXI_DMA_ID_WIDTH),
        .UW(CPTRA_AXI_DMA_USER_WIDTH)
    ) m_axi_if (.clk(core_clk), .rst_n(cptra_rst_b));

    logic firebridge_done;
    // Mode B: VeeR is bypassed, so the C firmware (not VeeR STDOUT) ends the sim.
    initial begin
        wait (firebridge_done);
        $display("FB_AHB: firebridge_done asserted, finishing simulation");
        $finish;
    end
    localparam int FB_AXI_S_COUNT        = 2;
    localparam int FB_AXI_DATA_WIDTH_MAX = CPTRA_AXI_DMA_DATA_WIDTH;
    localparam int FB_AXI_STRB_WIDTH_MAX = FB_AXI_DATA_WIDTH_MAX/8;
    localparam int FB_AXI_ID_WIDTH       = CPTRA_AXI_DMA_ID_WIDTH;

    logic [FB_AXI_S_COUNT-1:0][FB_AXI_ID_WIDTH-1:0]                 fb_s_axi_awid;
    logic [FB_AXI_S_COUNT-1:0][`CALIPTRA_AXI_DMA_ADDR_WIDTH-1:0]    fb_s_axi_awaddr;
    logic [FB_AXI_S_COUNT-1:0][7:0]                                 fb_s_axi_awlen;
    logic [FB_AXI_S_COUNT-1:0][`CALIPTRA_AXI_USER_WIDTH-1:0]        fb_s_axi_awuser;
    logic [FB_AXI_S_COUNT-1:0][2:0]                                 fb_s_axi_awsize;
    logic [FB_AXI_S_COUNT-1:0][1:0]                                 fb_s_axi_awburst;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_awlock;
    logic [FB_AXI_S_COUNT-1:0][3:0]                                 fb_s_axi_awcache;
    logic [FB_AXI_S_COUNT-1:0][2:0]                                 fb_s_axi_awprot;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_awvalid;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_awready;
    logic [FB_AXI_S_COUNT-1:0][FB_AXI_DATA_WIDTH_MAX-1:0]           fb_s_axi_wdata;
    logic [FB_AXI_S_COUNT-1:0][FB_AXI_STRB_WIDTH_MAX-1:0]           fb_s_axi_wstrb;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_wlast;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_wvalid;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_wready;
    logic [FB_AXI_S_COUNT-1:0][FB_AXI_ID_WIDTH-1:0]                 fb_s_axi_bid;
    logic [FB_AXI_S_COUNT-1:0][1:0]                                 fb_s_axi_bresp;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_bvalid;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_bready;
    logic [FB_AXI_S_COUNT-1:0][FB_AXI_ID_WIDTH-1:0]                 fb_s_axi_arid;
    logic [FB_AXI_S_COUNT-1:0][`CALIPTRA_AXI_DMA_ADDR_WIDTH-1:0]    fb_s_axi_araddr;
    logic [FB_AXI_S_COUNT-1:0][7:0]                                 fb_s_axi_arlen;
    logic [FB_AXI_S_COUNT-1:0][`CALIPTRA_AXI_USER_WIDTH-1:0]        fb_s_axi_aruser;
    logic [FB_AXI_S_COUNT-1:0][2:0]                                 fb_s_axi_arsize;
    logic [FB_AXI_S_COUNT-1:0][1:0]                                 fb_s_axi_arburst;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_arlock;
    logic [FB_AXI_S_COUNT-1:0][3:0]                                 fb_s_axi_arcache;
    logic [FB_AXI_S_COUNT-1:0][2:0]                                 fb_s_axi_arprot;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_arvalid;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_arready;
    logic [FB_AXI_S_COUNT-1:0][FB_AXI_ID_WIDTH-1:0]                 fb_s_axi_rid;
    logic [FB_AXI_S_COUNT-1:0][FB_AXI_DATA_WIDTH_MAX-1:0]           fb_s_axi_rdata;
    logic [FB_AXI_S_COUNT-1:0][1:0]                                 fb_s_axi_rresp;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_rlast;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_rvalid;
    logic [FB_AXI_S_COUNT-1:0]                                      fb_s_axi_rready;

    assign m_axi_bfm_if.awid    = `CALIPTRA_AXI_ID_WIDTH'(fb_s_axi_awid[0]);
    assign m_axi_bfm_if.awaddr  = fb_s_axi_awaddr[0][`CALIPTRA_SLAVE_ADDR_WIDTH(`CALIPTRA_SLAVE_SEL_SOC_IFC)-1:0];
    assign m_axi_bfm_if.awlen   = fb_s_axi_awlen[0];
    assign m_axi_bfm_if.awuser  = fb_s_axi_awuser[0];
    assign m_axi_bfm_if.awsize  = fb_s_axi_awsize[0];
    assign m_axi_bfm_if.awburst = fb_s_axi_awburst[0];
    assign m_axi_bfm_if.awlock  = fb_s_axi_awlock[0];
    assign m_axi_bfm_if.awvalid = fb_s_axi_awvalid[0];
    assign m_axi_bfm_if.wdata   = fb_s_axi_wdata[0][`CALIPTRA_AXI_DATA_WIDTH-1:0];
    assign m_axi_bfm_if.wstrb   = fb_s_axi_wstrb[0][(`CALIPTRA_AXI_DATA_WIDTH/8)-1:0];
    assign m_axi_bfm_if.wuser   = '0;
    assign m_axi_bfm_if.wlast   = fb_s_axi_wlast[0];
    assign m_axi_bfm_if.wvalid  = fb_s_axi_wvalid[0];
    assign m_axi_bfm_if.bready  = fb_s_axi_bready[0];
    assign m_axi_bfm_if.arid    = `CALIPTRA_AXI_ID_WIDTH'(fb_s_axi_arid[0]);
    assign m_axi_bfm_if.araddr  = fb_s_axi_araddr[0][`CALIPTRA_SLAVE_ADDR_WIDTH(`CALIPTRA_SLAVE_SEL_SOC_IFC)-1:0];
    assign m_axi_bfm_if.arlen   = fb_s_axi_arlen[0];
    assign m_axi_bfm_if.aruser  = fb_s_axi_aruser[0];
    assign m_axi_bfm_if.arsize  = fb_s_axi_arsize[0];
    assign m_axi_bfm_if.arburst = fb_s_axi_arburst[0];
    assign m_axi_bfm_if.arlock  = fb_s_axi_arlock[0];
    assign m_axi_bfm_if.arvalid = fb_s_axi_arvalid[0];
    assign m_axi_bfm_if.rready  = fb_s_axi_rready[0];

    assign fb_s_axi_awready[0] = m_axi_bfm_if.awready;
    assign fb_s_axi_wready [0] = m_axi_bfm_if.wready;
    assign fb_s_axi_bid    [0] = FB_AXI_ID_WIDTH'(m_axi_bfm_if.bid);
    assign fb_s_axi_bresp  [0] = m_axi_bfm_if.bresp;
    assign fb_s_axi_bvalid [0] = m_axi_bfm_if.bvalid;
    assign fb_s_axi_arready[0] = m_axi_bfm_if.arready;
    assign fb_s_axi_rid    [0] = FB_AXI_ID_WIDTH'(m_axi_bfm_if.rid);
    assign fb_s_axi_rdata  [0] = {{(FB_AXI_DATA_WIDTH_MAX-`CALIPTRA_AXI_DATA_WIDTH){1'b0}}, m_axi_bfm_if.rdata};
    assign fb_s_axi_rresp  [0] = m_axi_bfm_if.rresp;
    assign fb_s_axi_rlast  [0] = m_axi_bfm_if.rlast;
    assign fb_s_axi_rvalid [0] = m_axi_bfm_if.rvalid;

    logic [0:0][CPTRA_AXI_DMA_ID_WIDTH-1:0]       fb_m_axi_awid;
    logic [0:0][`CALIPTRA_AXI_DMA_ADDR_WIDTH-1:0] fb_m_axi_awaddr;
    logic [0:0][7:0]                              fb_m_axi_awlen;
    logic [0:0][2:0]                              fb_m_axi_awsize;
    logic [0:0][1:0]                              fb_m_axi_awburst;
    logic [0:0]                                   fb_m_axi_awlock;
    logic [0:0][3:0]                              fb_m_axi_awcache;
    logic [0:0][2:0]                              fb_m_axi_awprot;
    logic [0:0]                                   fb_m_axi_awvalid;
    logic [0:0]                                   fb_m_axi_awready;
    logic [0:0][CPTRA_AXI_DMA_DATA_WIDTH-1:0]     fb_m_axi_wdata;
    logic [0:0][(CPTRA_AXI_DMA_DATA_WIDTH/8)-1:0] fb_m_axi_wstrb;
    logic [0:0]                                   fb_m_axi_wlast;
    logic [0:0]                                   fb_m_axi_wvalid;
    logic [0:0]                                   fb_m_axi_wready;
    logic [0:0][CPTRA_AXI_DMA_ID_WIDTH-1:0]       fb_m_axi_bid;
    logic [0:0][1:0]                              fb_m_axi_bresp;
    logic [0:0]                                   fb_m_axi_bvalid;
    logic [0:0]                                   fb_m_axi_bready;
    logic [0:0][CPTRA_AXI_DMA_ID_WIDTH-1:0]       fb_m_axi_arid;
    logic [0:0][`CALIPTRA_AXI_DMA_ADDR_WIDTH-1:0] fb_m_axi_araddr;
    logic [0:0][7:0]                              fb_m_axi_arlen;
    logic [0:0][2:0]                              fb_m_axi_arsize;
    logic [0:0][1:0]                              fb_m_axi_arburst;
    logic [0:0]                                   fb_m_axi_arlock;
    logic [0:0][3:0]                              fb_m_axi_arcache;
    logic [0:0][2:0]                              fb_m_axi_arprot;
    logic [0:0]                                   fb_m_axi_arvalid;
    logic [0:0]                                   fb_m_axi_arready;
    logic [0:0][CPTRA_AXI_DMA_ID_WIDTH-1:0]       fb_m_axi_rid;
    logic [0:0][CPTRA_AXI_DMA_DATA_WIDTH-1:0]     fb_m_axi_rdata;
    logic [0:0][1:0]                              fb_m_axi_rresp;
    logic [0:0]                                   fb_m_axi_rlast;
    logic [0:0]                                   fb_m_axi_rvalid;
    logic [0:0]                                   fb_m_axi_rready;

    axi_if #(
        .AW(AXI_FIFO_ADDR_WIDTH),
        .DW(CPTRA_AXI_DMA_DATA_WIDTH),
        .IW(CPTRA_AXI_DMA_ID_WIDTH),
        .UW(CPTRA_AXI_DMA_USER_WIDTH)
    ) fb_axi_fifo_if (.clk(core_clk), .rst_n(cptra_rst_b));

    assign fb_m_axi_awid[0]    = m_axi_if.awid;
    assign fb_m_axi_awaddr[0]  = m_axi_if.awaddr;
    assign fb_m_axi_awlen[0]   = m_axi_if.awlen;
    assign fb_m_axi_awsize[0]  = m_axi_if.awsize;
    assign fb_m_axi_awburst[0] = m_axi_if.awburst;
    assign fb_m_axi_awlock[0]  = m_axi_if.awlock;
    assign fb_m_axi_awcache[0] = '0;
    assign fb_m_axi_awprot[0]  = '0;
    assign fb_m_axi_awvalid[0] = m_axi_if.awvalid;
    assign fb_m_axi_wdata[0]   = m_axi_if.wdata;
    assign fb_m_axi_wstrb[0]   = m_axi_if.wstrb;
    assign fb_m_axi_wlast[0]   = m_axi_if.wlast;
    assign fb_m_axi_wvalid[0]  = m_axi_if.wvalid;
    assign fb_m_axi_bready[0]  = m_axi_if.bready;
    assign fb_m_axi_arid[0]    = m_axi_if.arid;
    assign fb_m_axi_araddr[0]  = m_axi_if.araddr;
    assign fb_m_axi_arlen[0]   = m_axi_if.arlen;
    assign fb_m_axi_arsize[0]  = m_axi_if.arsize;
    assign fb_m_axi_arburst[0] = m_axi_if.arburst;
    assign fb_m_axi_arlock[0]  = m_axi_if.arlock;
    assign fb_m_axi_arcache[0] = '0;
    assign fb_m_axi_arprot[0]  = '0;
    assign fb_m_axi_arvalid[0] = m_axi_if.arvalid;
    assign fb_m_axi_rready[0]  = m_axi_if.rready;

    assign m_axi_if.awready = fb_m_axi_awready[0];
    assign m_axi_if.wready  = fb_m_axi_wready[0];
    assign m_axi_if.bid     = fb_m_axi_bid[0];
    assign m_axi_if.bresp   = fb_m_axi_bresp[0];
    assign m_axi_if.buser   = '0;
    assign m_axi_if.bvalid  = fb_m_axi_bvalid[0];
    assign m_axi_if.arready = fb_m_axi_arready[0];
    assign m_axi_if.rid     = fb_m_axi_rid[0];
    assign m_axi_if.rdata   = fb_m_axi_rdata[0];
    assign m_axi_if.rresp   = fb_m_axi_rresp[0];
    assign m_axi_if.ruser   = '0;
    assign m_axi_if.rlast   = fb_m_axi_rlast[0];
    assign m_axi_if.rvalid  = fb_m_axi_rvalid[0];

    assign fb_axi_fifo_if.awid    = fb_s_axi_awid[1];
    assign fb_axi_fifo_if.awaddr  = fb_s_axi_awaddr[1][AXI_FIFO_ADDR_WIDTH-1:0];
    assign fb_axi_fifo_if.awlen   = fb_s_axi_awlen[1];
    assign fb_axi_fifo_if.awuser  = '0;
    assign fb_axi_fifo_if.awsize  = fb_s_axi_awsize[1];
    assign fb_axi_fifo_if.awburst = fb_s_axi_awburst[1];
    assign fb_axi_fifo_if.awlock  = fb_s_axi_awlock[1];
    assign fb_axi_fifo_if.awvalid = fb_s_axi_awvalid[1];
    assign fb_axi_fifo_if.wdata   = fb_s_axi_wdata[1];
    assign fb_axi_fifo_if.wstrb   = fb_s_axi_wstrb[1];
    assign fb_axi_fifo_if.wuser   = '0;
    assign fb_axi_fifo_if.wlast   = fb_s_axi_wlast[1];
    assign fb_axi_fifo_if.wvalid  = fb_s_axi_wvalid[1];
    assign fb_axi_fifo_if.bready  = fb_s_axi_bready[1];
    assign fb_axi_fifo_if.arid    = fb_s_axi_arid[1];
    assign fb_axi_fifo_if.araddr  = fb_s_axi_araddr[1][AXI_FIFO_ADDR_WIDTH-1:0];
    assign fb_axi_fifo_if.arlen   = fb_s_axi_arlen[1];
    assign fb_axi_fifo_if.aruser  = '0;
    assign fb_axi_fifo_if.arsize  = fb_s_axi_arsize[1];
    assign fb_axi_fifo_if.arburst = fb_s_axi_arburst[1];
    assign fb_axi_fifo_if.arlock  = fb_s_axi_arlock[1];
    assign fb_axi_fifo_if.arvalid = fb_s_axi_arvalid[1];
    assign fb_axi_fifo_if.rready  = fb_s_axi_rready[1];

    assign fb_s_axi_awready[1] = fb_axi_fifo_if.awready;
    assign fb_s_axi_wready [1] = fb_axi_fifo_if.wready;
    assign fb_s_axi_bid    [1] = fb_axi_fifo_if.bid;
    assign fb_s_axi_bresp  [1] = fb_axi_fifo_if.bresp;
    assign fb_s_axi_bvalid [1] = fb_axi_fifo_if.bvalid;
    assign fb_s_axi_arready[1] = fb_axi_fifo_if.arready;
    assign fb_s_axi_rid    [1] = fb_axi_fifo_if.rid;
    assign fb_s_axi_rdata  [1] = fb_axi_fifo_if.rdata;
    assign fb_s_axi_rresp  [1] = fb_axi_fifo_if.rresp;
    assign fb_s_axi_rlast  [1] = fb_axi_fifo_if.rlast;
    assign fb_s_axi_rvalid [1] = fb_axi_fifo_if.rvalid;

    fb_axi_vip #(
        .S_COUNT(FB_AXI_S_COUNT),
        .M_COUNT(1),
        .S_AXI_DATA_WIDTH_MAX(FB_AXI_DATA_WIDTH_MAX),
        .S_AXI_DATA_WIDTH('{default: FB_AXI_DATA_WIDTH_MAX, 0: `CALIPTRA_AXI_DATA_WIDTH, 1: CPTRA_AXI_DMA_DATA_WIDTH}),
        .S_AXI_ID_WIDTH(FB_AXI_ID_WIDTH),
        .S_AXI_ADDR_WIDTH(`CALIPTRA_AXI_DMA_ADDR_WIDTH),
        .S_AXI_USER_WIDTH(`CALIPTRA_AXI_USER_WIDTH),
        .S_AXI_USER_VALUE(32'hFFFF_FFFF),  // Matches CPTRA_DEF_MBOX_VALID_AXI_USER for mbox access
        .S_AXI_BASE_ADDR('{default: '0, 0: `CALIPTRA_AXI_DMA_ADDR_WIDTH'h3000_0000, 1: AXI_FIFO_BASE_ADDR}),
        .S_AXI_REGION_ADDR_WIDTH('{default: `CALIPTRA_AXI_DMA_ADDR_WIDTH, 0: `CALIPTRA_SLAVE_ADDR_WIDTH(`CALIPTRA_SLAVE_SEL_SOC_IFC), 1: AXI_FIFO_ADDR_WIDTH}),
        .M_AXI_DATA_WIDTH_MAX(FB_AXI_DATA_WIDTH_MAX),
        .M_AXI_DATA_WIDTH('{default: CPTRA_AXI_DMA_DATA_WIDTH, 0: CPTRA_AXI_DMA_DATA_WIDTH}),
        .M_AXI_ADDR_WIDTH(`CALIPTRA_AXI_DMA_ADDR_WIDTH),
        .M_AXI_ID_WIDTH(CPTRA_AXI_DMA_ID_WIDTH)
    ) fb_axi_i (
        .clk(core_clk),
        .rstn(cptra_rst_b),
        .firebridge_done(firebridge_done),
        .s_axi_awid(fb_s_axi_awid),
        .s_axi_awaddr(fb_s_axi_awaddr),
        .s_axi_awlen(fb_s_axi_awlen),
        .s_axi_awuser(fb_s_axi_awuser),
        .s_axi_awsize(fb_s_axi_awsize),
        .s_axi_awburst(fb_s_axi_awburst),
        .s_axi_awlock(fb_s_axi_awlock),
        .s_axi_awcache(fb_s_axi_awcache),
        .s_axi_awprot(fb_s_axi_awprot),
        .s_axi_awvalid(fb_s_axi_awvalid),
        .s_axi_awready(fb_s_axi_awready),
        .s_axi_wdata(fb_s_axi_wdata),
        .s_axi_wstrb(fb_s_axi_wstrb),
        .s_axi_wlast(fb_s_axi_wlast),
        .s_axi_wvalid(fb_s_axi_wvalid),
        .s_axi_wready(fb_s_axi_wready),
        .s_axi_bid(fb_s_axi_bid),
        .s_axi_bresp(fb_s_axi_bresp),
        .s_axi_bvalid(fb_s_axi_bvalid),
        .s_axi_bready(fb_s_axi_bready),
        .s_axi_arid(fb_s_axi_arid),
        .s_axi_araddr(fb_s_axi_araddr),
        .s_axi_arlen(fb_s_axi_arlen),
        .s_axi_aruser(fb_s_axi_aruser),
        .s_axi_arsize(fb_s_axi_arsize),
        .s_axi_arburst(fb_s_axi_arburst),
        .s_axi_arlock(fb_s_axi_arlock),
        .s_axi_arcache(fb_s_axi_arcache),
        .s_axi_arprot(fb_s_axi_arprot),
        .s_axi_arvalid(fb_s_axi_arvalid),
        .s_axi_arready(fb_s_axi_arready),
        .s_axi_rid(fb_s_axi_rid),
        .s_axi_rdata(fb_s_axi_rdata),
        .s_axi_rresp(fb_s_axi_rresp),
        .s_axi_rlast(fb_s_axi_rlast),
        .s_axi_rvalid(fb_s_axi_rvalid),
        .s_axi_rready(fb_s_axi_rready),
        .m_axi_awid(fb_m_axi_awid),
        .m_axi_awaddr(fb_m_axi_awaddr),
        .m_axi_awlen(fb_m_axi_awlen),
        .m_axi_awsize(fb_m_axi_awsize),
        .m_axi_awburst(fb_m_axi_awburst),
        .m_axi_awlock(fb_m_axi_awlock),
        .m_axi_awcache(fb_m_axi_awcache),
        .m_axi_awprot(fb_m_axi_awprot),
        .m_axi_awvalid(fb_m_axi_awvalid),
        .m_axi_awready(fb_m_axi_awready),
        .m_axi_wdata(fb_m_axi_wdata),
        .m_axi_wstrb(fb_m_axi_wstrb),
        .m_axi_wlast(fb_m_axi_wlast),
        .m_axi_wvalid(fb_m_axi_wvalid),
        .m_axi_wready(fb_m_axi_wready),
        .m_axi_bid(fb_m_axi_bid),
        .m_axi_bresp(fb_m_axi_bresp),
        .m_axi_bvalid(fb_m_axi_bvalid),
        .m_axi_bready(fb_m_axi_bready),
        .m_axi_arid(fb_m_axi_arid),
        .m_axi_araddr(fb_m_axi_araddr),
        .m_axi_arlen(fb_m_axi_arlen),
        .m_axi_arsize(fb_m_axi_arsize),
        .m_axi_arburst(fb_m_axi_arburst),
        .m_axi_arlock(fb_m_axi_arlock),
        .m_axi_arcache(fb_m_axi_arcache),
        .m_axi_arprot(fb_m_axi_arprot),
        .m_axi_arvalid(fb_m_axi_arvalid),
        .m_axi_arready(fb_m_axi_arready),
        .m_axi_rid(fb_m_axi_rid),
        .m_axi_rdata(fb_m_axi_rdata),
        .m_axi_rresp(fb_m_axi_rresp),
        .m_axi_rlast(fb_m_axi_rlast),
        .m_axi_rvalid(fb_m_axi_rvalid),
        .m_axi_rready(fb_m_axi_rready)
    );

    logic ready_for_fuses;
    logic ready_for_mb_processing;
    logic mailbox_data_avail;
    logic mbox_sram_cs;
    logic mbox_sram_we;
    logic [CPTRA_MBOX_ADDR_W-1:0] mbox_sram_addr;
    logic [CPTRA_MBOX_DATA_AND_ECC_W-1:0] mbox_sram_wdata;
    logic [CPTRA_MBOX_DATA_AND_ECC_W-1:0] mbox_sram_rdata;

    logic imem_cs;
    logic [`CALIPTRA_IMEM_ADDR_WIDTH-1:0] imem_addr;
    logic [`CALIPTRA_IMEM_DATA_WIDTH-1:0] imem_rdata;

    //device lifecycle
    security_state_t security_state;

    logic ss_ocp_lock_en;

    ras_test_ctrl_t ras_test_ctrl;
    axi_complex_ctrl_t axi_complex_ctrl;
    logic [63:0] generic_input_wires;
    logic        etrng_req;
    logic  [3:0] itrng_data;
    logic        itrng_valid;

    logic cptra_error_fatal;
    logic cptra_error_non_fatal;

    //Interrupt flags
    logic int_flag;
    logic cycleCnt_smpl_en;

    //Reset flags
    logic assert_hard_rst_flag;
    logic deassert_hard_rst_flag;
    logic assert_rst_flag_from_service;
    logic deassert_rst_flag_from_service;

    el2_mem_if el2_mem_export ();
    abr_mem_if abr_memory_export();

`ifndef VERILATOR
    always
    begin : clk_gen
      core_clk = #5ns ~core_clk;
    end // clk_gen
`endif

initial begin
    logic [0:`CLP_OBF_KEY_DWORDS-1][31:0] cptra_obfkey_tb_fb;

    cptra_pwrgood = 1'b0;
    cptra_rst_b = 1'b0;
    BootFSM_BrkPoint = 1'b1;
    cptra_obfkey_tb_fb = 256'h31358e8af34d6ac31c958bbd5c8fb33c334714bffb41700d28b07f11cfe891e7;
    for (int dword = 0; dword < $bits(cptra_obf_key)/32; dword++) begin
        cptra_obf_key[dword] = cptra_obfkey_tb_fb[dword];
    end
    for (int dword = 0; dword < `CLP_CSR_HMAC_KEY_DWORDS; dword++) begin
        cptra_csr_hmac_key[dword] = 32'h0b0b0b0b;
    end
    strap_ss_key_release_key_size = 16'h40;
    strap_ss_key_release_base_addr = AXI_SRAM_BASE_ADDR;
    ss_ocp_lock_en = 1'b0;
    generic_input_wires = '0;
    repeat (15) @(posedge core_clk);
    cptra_pwrgood = 1'b1;
    repeat (5) @(posedge core_clk);
    cptra_rst_b = 1'b1;
end

// Drive cptra_pwrgood/cptra_rst_b in response to warm/cold reset flags from TB services
// (soc_bfm handles this in the non-FB path, so FB needs its own handler)
// Also handles cptra_error_fatal (WDT NMI) → warm reset (matches soc_bfm behavior).
logic [5:0] fb_fatal_cnt;
always @(posedge core_clk or negedge cptra_pwrgood) begin
    // deassert flags have HIGHEST priority — must fire even when cptra_pwrgood=0
    // (original code had !cptra_pwrgood first, which blocked deassert_hard_rst_flag
    //  during cold-reset and left cptra_pwrgood stuck at 0 forever)
    if (deassert_hard_rst_flag) begin
        cptra_pwrgood <= 1'b1;
        fb_fatal_cnt  <= '0;
    end else if (deassert_rst_flag_from_service) begin
        cptra_rst_b <= 1'b1;
    end else if (assert_hard_rst_flag) begin
        cptra_pwrgood <= 1'b0;
        cptra_rst_b   <= 1'b0;
        fb_fatal_cnt  <= '0;
    end else if (assert_rst_flag_from_service) begin
        cptra_rst_b <= 1'b0;
        fb_fatal_cnt <= '0;
    end else if (!cptra_pwrgood) begin
        fb_fatal_cnt <= '0;
    end else if (cptra_error_fatal && cptra_rst_b && fb_fatal_cnt == '0) begin
        fb_fatal_cnt <= 6'd1;
    end else if (fb_fatal_cnt != '0) begin
        fb_fatal_cnt <= fb_fatal_cnt + 6'd1;
        if (fb_fatal_cnt == 6'd10)  cptra_rst_b  <= 1'b0;
        if (fb_fatal_cnt == 6'd40) begin cptra_rst_b <= 1'b1; fb_fatal_cnt <= '0; end
    end
end


// JTAG DPI
jtagdpi #(
    .Name           ("jtag0"),
    .ListenPort     (63224)
) jtagdpi (
    .clk_i          (core_clk),
    .rst_ni         (cptra_rst_b),
    .jtag_tck       (jtag_tck),
    .jtag_tms       (jtag_tms),
    .jtag_tdi       (jtag_tdi),
    .jtag_tdo       (jtag_tdo),
    .jtag_trst_n    (jtag_trst_n),
    .jtag_srst_n    ()
);

   //=========================================================================-
   // DUT instance
   //=========================================================================-
caliptra_top caliptra_top_dut (
    .cptra_pwrgood              (cptra_pwrgood),
    .cptra_rst_b                (cptra_rst_b),
    .clk                        (core_clk),

    .cptra_obf_key              (cptra_obf_key),
    .cptra_obf_uds_seed_vld     ('0), //validated at caliptra-ss
    .cptra_obf_uds_seed         ('0), //validated at caliptra-ss
    .cptra_obf_field_entropy_vld('0), //validated at caliptra-ss
    .cptra_obf_field_entropy    ('0), //validated at caliptra-ss
    .cptra_csr_hmac_key         (cptra_csr_hmac_key),

    .jtag_tck(jtag_tck),
    .jtag_tdi(jtag_tdi),
    .jtag_tms(jtag_tms),
    .jtag_trst_n(jtag_trst_n),
    .jtag_tdo(jtag_tdo),
    .jtag_tdoEn(jtag_tdoEn),
    
    //SoC AXI Interface
    .s_axi_w_if(m_axi_bfm_if.w_sub),
    .s_axi_r_if(m_axi_bfm_if.r_sub),

    //AXI DMA Interface
    .m_axi_w_if(m_axi_if.w_mgr),
    .m_axi_r_if(m_axi_if.r_mgr),

    .el2_mem_export(el2_mem_export.veer_sram_src),
    .abr_memory_export(abr_memory_export.req),
    
    .ready_for_fuses(ready_for_fuses),
    .ready_for_mb_processing(ready_for_mb_processing),
    .ready_for_runtime(),

    .mbox_sram_cs(mbox_sram_cs),
    .mbox_sram_we(mbox_sram_we),
    .mbox_sram_addr(mbox_sram_addr),
    .mbox_sram_wdata(mbox_sram_wdata),
    .mbox_sram_rdata(mbox_sram_rdata),
        
    .imem_cs(imem_cs),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),

    .mailbox_data_avail(mailbox_data_avail),
    .mailbox_flow_done(),
    .BootFSM_BrkPoint(BootFSM_BrkPoint),

    .recovery_data_avail(recovery_data_avail),
    .recovery_image_activated(1'b0),

    //SoC Interrupts
    .cptra_error_fatal    (cptra_error_fatal    ),
    .cptra_error_non_fatal(cptra_error_non_fatal),

`ifdef CALIPTRA_INTERNAL_TRNG
    .etrng_req             (etrng_req),
    .itrng_data            (itrng_data),
    .itrng_valid           (itrng_valid),
`else
    .etrng_req             (),
    .itrng_data            (4'b0),
    .itrng_valid           (1'b0),
`endif

    // Subsystem mode straps, tested in subsystem bench
    .strap_ss_caliptra_base_addr                            (64'hba5e_ba11),
    .strap_ss_mci_base_addr                                 (64'h0),
    .strap_ss_recovery_ifc_base_addr                        (64'h0),
    .strap_ss_external_staging_area_base_addr               (64'h0),
    .strap_ss_otp_fc_base_addr                              (64'h0),
    .strap_ss_uds_seed_base_addr                            (64'h0),
    .strap_ss_key_release_base_addr                         ,
    .strap_ss_key_release_key_size                          ,
    .strap_ss_prod_debug_unlock_auth_pk_hash_reg_bank_offset(32'h0),
    .strap_ss_num_of_prod_debug_unlock_auth_pk_hashes       (32'h0),
    .strap_ss_caliptra_dma_axi_user                         (32'h0),
    .strap_ss_strap_generic_0                               (32'h0),
    .strap_ss_strap_generic_1                               (32'h0),
    .strap_ss_strap_generic_2                               (32'h0),
    .strap_ss_strap_generic_3                               (32'h0),
    .ss_debug_intent                                        ( 1'b0),

    // Subsystem mode constant strap input indicating OCP LOCK configuration is enabled
    .ss_ocp_lock_en                                         (ss_ocp_lock_en),

    // Subsystem mode debug outputs
    .ss_dbg_manuf_enable    (),
    .ss_soc_dbg_unlock_level(),

    // Subsystem mode firmware execution control
    .ss_generic_fw_exec_ctrl(),

    .generic_input_wires (generic_input_wires ),
    .generic_output_wires(                    ),

    // RISC-V Trace Ports
    .trace_rv_i_insn_ip     (),
    .trace_rv_i_address_ip  (),
    .trace_rv_i_valid_ip    (),
    .trace_rv_i_exception_ip(),
    .trace_rv_i_ecause_ip   (),
    .trace_rv_i_interrupt_ip(),
    .trace_rv_i_tval_ip     (),

    .security_state(security_state),
    .scan_mode     (scan_mode)
);


`ifdef CALIPTRA_INTERNAL_TRNG
    //=========================================================================-
    // Physical RNG used for Internal TRNG
    //=========================================================================-
physical_rng physical_rng (
    .clk    (core_clk),
    .enable (etrng_req),
    .data   (itrng_data),
    .valid  (itrng_valid)
);
`endif

   //=========================================================================-
   // Services for SRAM exports, STDOUT, etc
   //=========================================================================-
caliptra_top_tb_services #(
    .UVM_TB(0)
) tb_services_i (
    .clk(core_clk),

    .cptra_rst_b(cptra_rst_b),

    // Caliptra Memory Export Interface
    .el2_mem_export (el2_mem_export.veer_sram_sink),
    .abr_memory_export (abr_memory_export.resp),

    //SRAM interface for mbox
    .mbox_sram_cs   (mbox_sram_cs   ),
    .mbox_sram_we   (mbox_sram_we   ),
    .mbox_sram_addr (mbox_sram_addr ),
    .mbox_sram_wdata(mbox_sram_wdata),
    .mbox_sram_rdata(mbox_sram_rdata),

    //SRAM interface for imem
    .imem_cs   (imem_cs   ),
    .imem_addr (imem_addr ),
    .imem_rdata(imem_rdata),

    // Security State
    .security_state(security_state),

    //Scan mode
    .scan_mode(scan_mode),

    // TB Controls
    .ras_test_ctrl(ras_test_ctrl),
    .cycleCnt(cycleCnt),
    .axi_complex_ctrl(axi_complex_ctrl),

    //Interrupt flags
    .int_flag(int_flag),
    .cycleCnt_smpl_en(cycleCnt_smpl_en),

    //Reset flags
    .assert_hard_rst_flag(assert_hard_rst_flag),
    .deassert_hard_rst_flag(deassert_hard_rst_flag),

    .assert_rst_flag(assert_rst_flag_from_service),
    .deassert_rst_flag(deassert_rst_flag_from_service),
    
    .cptra_uds_tb(cptra_uds_rand),
    .cptra_fe_tb(cptra_fe_rand),
    .cptra_obf_key_tb(cptra_obf_key_tb),
    .cptra_hek_tb(cptra_hek_rand),

    .axi_error_inj_en(axi_error_inj_en)

);

caliptra_top_tb_axi_fifo #(
    .AW(AXI_FIFO_ADDR_WIDTH),
    .DW(CPTRA_AXI_DMA_DATA_WIDTH),
    .UW(CPTRA_AXI_DMA_USER_WIDTH),
    .IW(CPTRA_AXI_DMA_ID_WIDTH),
    .DEPTH(AXI_FIFO_SIZE_BYTES)
) tb_axi_fifo_i (
    .clk  (core_clk),
    .rst_n(cptra_rst_b),

    .s_axi_w_if(fb_axi_fifo_if.w_sub),
    .s_axi_r_if(fb_axi_fifo_if.r_sub),

    .auto_push            (axi_complex_ctrl.fifo_auto_push),
    .auto_pop             (axi_complex_ctrl.fifo_auto_pop),
    .fifo_clear           (axi_complex_ctrl.fifo_clear),
    .en_recovery_emulation(axi_complex_ctrl.en_recovery_emulation),
    .recovery_data_avail  (recovery_data_avail),
    .dma_gen_done         (axi_complex_ctrl.dma_gen_done),
    .dma_gen_block_size   (axi_complex_ctrl.dma_gen_block_size)
);

//=========================================================================- 
// SVA
//=========================================================================-
caliptra_top_sva sva();

endmodule
