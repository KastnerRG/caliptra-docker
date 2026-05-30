`timescale 1ns/1ps

module fb_axi_vip #(
  parameter
  S_COUNT          = 1,
  M_COUNT          = 1,
  MAX_S_COUNT      = 16,
  MAX_M_COUNT      = 16,

  M_AXI_ADDR_WIDTH  = 32,
  M_AXI_ID_WIDTH    = 6,
  M_AXI_DATA_WIDTH_MAX  = 128,
  parameter int M_AXI_DATA_WIDTH  [MAX_M_COUNT] = '{default: M_AXI_DATA_WIDTH_MAX},
  parameter int M_AXI_STRB_WIDTH_MAX  = (M_AXI_DATA_WIDTH_MAX/8),
  S_AXI_ID_WIDTH    = 6,
  S_AXI_ADDR_WIDTH  = 40,
  S_AXI_USER_WIDTH  = 32,
  S_AXI_USER_VALUE  = 32'h0,
  S_AXI_DATA_WIDTH_MAX  = 128,

  parameter int S_AXI_DATA_WIDTH  [MAX_S_COUNT] = '{default: S_AXI_DATA_WIDTH_MAX},
  parameter int S_AXI_STRB_WIDTH_MAX  = (S_AXI_DATA_WIDTH_MAX/8),
  parameter bit [M_AXI_ADDR_WIDTH-1:0] S_AXI_BASE_ADDR [MAX_S_COUNT] = '{default: 32'hA0000000},
  parameter int S_AXI_REGION_ADDR_WIDTH [MAX_S_COUNT] = '{default: M_AXI_ADDR_WIDTH},

  VALID_PROB        = 1000,
  READY_PROB        = 1000
)(
	  input  bit clk,
	  input  bit rstn,
	  output bit firebridge_done,

  // AXI Slave
  output bit [S_COUNT-1:0][S_AXI_ID_WIDTH -1:0]   s_axi_awid   ,
  output bit [S_COUNT-1:0][S_AXI_ADDR_WIDTH-1:0]  s_axi_awaddr ,
  output bit [S_COUNT-1:0][7:0]                   s_axi_awlen  ,
  output bit [S_COUNT-1:0][S_AXI_USER_WIDTH-1:0]  s_axi_awuser ,
  output bit [S_COUNT-1:0][2:0]                   s_axi_awsize ,
  output bit [S_COUNT-1:0][1:0]                   s_axi_awburst,
  output bit [S_COUNT-1:0]                        s_axi_awlock ,
  output bit [S_COUNT-1:0][3:0]                   s_axi_awcache,
  output bit [S_COUNT-1:0][2:0]                   s_axi_awprot ,
  output bit [S_COUNT-1:0]                        s_axi_awvalid,
  input  bit [S_COUNT-1:0]                        s_axi_awready ,
  output bit [S_COUNT-1:0][S_AXI_DATA_WIDTH_MAX-1:0]  s_axi_wdata  ,
  output bit [S_COUNT-1:0][S_AXI_STRB_WIDTH_MAX-1:0]  s_axi_wstrb  ,
  output bit [S_COUNT-1:0]                        s_axi_wlast  ,
  output bit [S_COUNT-1:0]                        s_axi_wvalid ,
  input  bit [S_COUNT-1:0]                        s_axi_wready ,
  input  bit [S_COUNT-1:0][S_AXI_ID_WIDTH-1:0]    s_axi_bid    ,
  input  bit [S_COUNT-1:0][1:0]                   s_axi_bresp  ,
  input  bit [S_COUNT-1:0]                        s_axi_bvalid ,
  output bit [S_COUNT-1:0]                        s_axi_bready ,
  output bit [S_COUNT-1:0][S_AXI_ID_WIDTH-1:0]    s_axi_arid   ,
  output bit [S_COUNT-1:0][S_AXI_ADDR_WIDTH-1:0]  s_axi_araddr ,
  output bit [S_COUNT-1:0][7:0]                   s_axi_arlen  ,
  output bit [S_COUNT-1:0][S_AXI_USER_WIDTH-1:0]  s_axi_aruser ,
  output bit [S_COUNT-1:0][2:0]                   s_axi_arsize ,
  output bit [S_COUNT-1:0][1:0]                   s_axi_arburst,
  output bit [S_COUNT-1:0]                        s_axi_arlock ,
  output bit [S_COUNT-1:0][3:0]                   s_axi_arcache,
  output bit [S_COUNT-1:0][2:0]                   s_axi_arprot ,
  output bit [S_COUNT-1:0]                        s_axi_arvalid,
  input  bit [S_COUNT-1:0]                        s_axi_arready ,
  input  bit [S_COUNT-1:0][S_AXI_ID_WIDTH-1:0]    s_axi_rid    ,
  input  bit [S_COUNT-1:0][S_AXI_DATA_WIDTH_MAX-1:0]  s_axi_rdata  ,
  input  bit [S_COUNT-1:0][1:0]                   s_axi_rresp  ,
  input  bit [S_COUNT-1:0]                        s_axi_rlast  ,
  input  bit [S_COUNT-1:0]                        s_axi_rvalid ,
  output bit [S_COUNT-1:0]                        s_axi_rready ,
  // AXI Masters
  input  bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    m_axi_awid   ,
  input  bit [M_COUNT-1:0][M_AXI_ADDR_WIDTH-1:0]  m_axi_awaddr ,
  input  bit [M_COUNT-1:0][7:0]                   m_axi_awlen  ,
  input  bit [M_COUNT-1:0][2:0]                   m_axi_awsize ,
  input  bit [M_COUNT-1:0][1:0]                   m_axi_awburst,
  input  bit [M_COUNT-1:0]                        m_axi_awlock ,
  input  bit [M_COUNT-1:0][3:0]                   m_axi_awcache,
  input  bit [M_COUNT-1:0][2:0]                   m_axi_awprot ,
  input  bit [M_COUNT-1:0]                        m_axi_awvalid,
  output bit [M_COUNT-1:0]                        m_axi_awready,
  input  bit [M_COUNT-1:0][M_AXI_DATA_WIDTH_MAX-1:0]  m_axi_wdata  ,
  input  bit [M_COUNT-1:0][M_AXI_STRB_WIDTH_MAX-1:0]  m_axi_wstrb  ,
  input  bit [M_COUNT-1:0]                        m_axi_wlast  ,
  input  bit [M_COUNT-1:0]                        m_axi_wvalid ,
  output bit [M_COUNT-1:0]                        m_axi_wready ,
  output bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    m_axi_bid    ,
  output bit [M_COUNT-1:0][1:0]                   m_axi_bresp  ,
  output bit [M_COUNT-1:0]                        m_axi_bvalid ,
  input  bit [M_COUNT-1:0]                        m_axi_bready ,
  input  bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    m_axi_arid   ,
  input  bit [M_COUNT-1:0][M_AXI_ADDR_WIDTH-1:0]  m_axi_araddr ,
  input  bit [M_COUNT-1:0][7:0]                   m_axi_arlen  ,
  input  bit [M_COUNT-1:0][2:0]                   m_axi_arsize ,
  input  bit [M_COUNT-1:0][1:0]                   m_axi_arburst,
  input  bit [M_COUNT-1:0]                        m_axi_arlock ,
  input  bit [M_COUNT-1:0][3:0]                   m_axi_arcache,
  input  bit [M_COUNT-1:0][2:0]                   m_axi_arprot ,
  input  bit [M_COUNT-1:0]                        m_axi_arvalid,
  output bit [M_COUNT-1:0]                        m_axi_arready,
  output bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    m_axi_rid    ,
  output bit [M_COUNT-1:0][M_AXI_DATA_WIDTH_MAX-1:0]  m_axi_rdata  ,
	  output bit [M_COUNT-1:0][1:0]                   m_axi_rresp  ,
	  output bit [M_COUNT-1:0]                        m_axi_rlast  ,
	  output bit [M_COUNT-1:0]                        m_axi_rvalid ,
	  input  bit [M_COUNT-1:0]                        m_axi_rready
	);
  chandle p_mem;
  genvar m;
  localparam  
	    LSB = $clog2(M_AXI_DATA_WIDTH_MAX)-3,
		    OPT_LOCK          = 1'b0,
		    OPT_LOCKID        = 1'b1,
		    OPT_LOWPOWER      = 1'b0,
		    // 10us@1ps: covers cptra_pwrgood=0 cold-reset (20 cyc) + slave re-init
		    FB_AXI_TIMEOUT    = 10000000,
		    FB_AXI_RESP_TIMEOUT = 10000000,
		    S_AXI0_DATA_WIDTH = S_AXI_DATA_WIDTH[0],
		    S_BYTES           = (S_AXI0_DATA_WIDTH/8),
		    S_SIZE            = $clog2(S_BYTES),
		    M_AXI_ID_COUNT    = (1 << M_AXI_ID_WIDTH);

  bit  [M_COUNT-1:0]                            ren;
  bit  [M_COUNT-1:0][M_AXI_ADDR_WIDTH-LSB-1:0]  raddr;
  bit  [M_COUNT-1:0][M_AXI_DATA_WIDTH_MAX-1:0]      rdata;
	  bit  [M_COUNT-1:0]                            wen;
	  bit  [M_COUNT-1:0][M_AXI_ADDR_WIDTH-LSB-1:0]  waddr;
	  bit  [M_COUNT-1:0][M_AXI_DATA_WIDTH_MAX-1:0]      wdata;
	  bit  [M_COUNT-1:0][M_AXI_DATA_WIDTH_MAX/8-1:0]    wstrb;

	  function automatic bit addr_in_s_region(input bit [M_AXI_ADDR_WIDTH-1:0] addr, input int s);
	    bit [M_AXI_ADDR_WIDTH-1:0] mask;
	    mask = {M_AXI_ADDR_WIDTH{1'b1}} << S_AXI_REGION_ADDR_WIDTH[s];
	    return (addr & mask) == (M_AXI_ADDR_WIDTH'(S_AXI_BASE_ADDR[s]) & mask);
	  endfunction

  function automatic int get_s_index(input bit [M_AXI_ADDR_WIDTH-1:0] addr);
    int index = -1;
    for (int s=0; s < S_COUNT; s++) begin
      if (addr_in_s_region(addr, s)) begin
        index = s;
        break;
      end
    end
    return index;
  endfunction

  initial begin
    if (M_COUNT != 1)
      $fatal(1, "FB_AXI: only one m_axi initiator is supported by the lightweight xbar path");
    if (S_AXI_ID_WIDTH != M_AXI_ID_WIDTH)
      $fatal(1, "FB_AXI: S/M AXI ID width conversion is unsupported");
    for (int s=0; s < S_COUNT; s++) begin
      if (S_AXI_DATA_WIDTH[s] > S_AXI_DATA_WIDTH_MAX)
        $fatal(1, "FB_AXI: S_AXI_DATA_WIDTH[%0d] (%0d) exceeds S_AXI_DATA_WIDTH_MAX (%0d)",
               s, S_AXI_DATA_WIDTH[s], S_AXI_DATA_WIDTH_MAX);
    end
    for (int mm=0; mm < M_COUNT; mm++) begin
      if (M_AXI_DATA_WIDTH[mm] != M_AXI_DATA_WIDTH_MAX)
        $fatal(1, "FB_AXI: M-side width conversion is unsupported: M_AXI_DATA_WIDTH[%0d]=%0d M_AXI_DATA_WIDTH_MAX=%0d",
               mm, M_AXI_DATA_WIDTH[mm], M_AXI_DATA_WIDTH_MAX);
    end
  end

`ifdef VERILATOR
  function byte get_clk();
    get_clk = 8'(clk);
  endfunction
  export "DPI-C" function get_clk;

  import "DPI-C" context function void at_posedge_clk();
  import "DPI-C" context function void step_time_veri();

  `define TIMESTEP step_time_veri()
  `define FB_PAUSE_WHILE(expr) while (expr) step_time_veri()

`else
  task at_posedge_clk();
    @(posedge clk) #10ps;
  endtask

  `define TIMESTEP #10ps
  `define FB_PAUSE_WHILE(expr) wait (!(expr))
`endif

  bit [S_COUNT-1:0][S_AXI_ID_WIDTH -1:0]   cpu_s_axi_awid;
  bit [S_COUNT-1:0][S_AXI_ADDR_WIDTH-1:0]  cpu_s_axi_awaddr;
  bit [S_COUNT-1:0][7:0]                   cpu_s_axi_awlen;
  bit [S_COUNT-1:0][S_AXI_USER_WIDTH-1:0]  cpu_s_axi_awuser;
  bit [S_COUNT-1:0][2:0]                   cpu_s_axi_awsize;
  bit [S_COUNT-1:0][1:0]                   cpu_s_axi_awburst;
  bit [S_COUNT-1:0]                        cpu_s_axi_awlock;
  bit [S_COUNT-1:0][3:0]                   cpu_s_axi_awcache;
  bit [S_COUNT-1:0][2:0]                   cpu_s_axi_awprot;
  bit [S_COUNT-1:0]                        cpu_s_axi_awvalid;
  bit [S_COUNT-1:0][S_AXI_DATA_WIDTH_MAX-1:0] cpu_s_axi_wdata;
  bit [S_COUNT-1:0][S_AXI_STRB_WIDTH_MAX-1:0] cpu_s_axi_wstrb;
  bit [S_COUNT-1:0]                        cpu_s_axi_wlast;
  bit [S_COUNT-1:0]                        cpu_s_axi_wvalid;
  bit [S_COUNT-1:0]                        cpu_s_axi_bready;
  bit [S_COUNT-1:0][S_AXI_ID_WIDTH-1:0]    cpu_s_axi_arid;
  bit [S_COUNT-1:0][S_AXI_ADDR_WIDTH-1:0]  cpu_s_axi_araddr;
  bit [S_COUNT-1:0][7:0]                   cpu_s_axi_arlen;
  bit [S_COUNT-1:0][S_AXI_USER_WIDTH-1:0]  cpu_s_axi_aruser;
  bit [S_COUNT-1:0][2:0]                   cpu_s_axi_arsize;
  bit [S_COUNT-1:0][1:0]                   cpu_s_axi_arburst;
  bit [S_COUNT-1:0]                        cpu_s_axi_arlock;
  bit [S_COUNT-1:0][3:0]                   cpu_s_axi_arcache;
  bit [S_COUNT-1:0][2:0]                   cpu_s_axi_arprot;
  bit [S_COUNT-1:0]                        cpu_s_axi_arvalid;
  bit [S_COUNT-1:0]                        cpu_s_axi_rready;
  bit [S_COUNT-1:0]                        cpu_s_axi_busy;

  bit [S_COUNT-1:0][S_AXI_ID_WIDTH -1:0]   xbar_s_axi_awid;
  bit [S_COUNT-1:0][S_AXI_ADDR_WIDTH-1:0]  xbar_s_axi_awaddr;
  bit [S_COUNT-1:0][7:0]                   xbar_s_axi_awlen;
  bit [S_COUNT-1:0][S_AXI_USER_WIDTH-1:0]  xbar_s_axi_awuser;
  bit [S_COUNT-1:0][2:0]                   xbar_s_axi_awsize;
  bit [S_COUNT-1:0][1:0]                   xbar_s_axi_awburst;
  bit [S_COUNT-1:0]                        xbar_s_axi_awlock;
  bit [S_COUNT-1:0][3:0]                   xbar_s_axi_awcache;
  bit [S_COUNT-1:0][2:0]                   xbar_s_axi_awprot;
  bit [S_COUNT-1:0]                        xbar_s_axi_awvalid;
  bit [S_COUNT-1:0][S_AXI_DATA_WIDTH_MAX-1:0] xbar_s_axi_wdata;
  bit [S_COUNT-1:0][S_AXI_STRB_WIDTH_MAX-1:0] xbar_s_axi_wstrb;
  bit [S_COUNT-1:0]                        xbar_s_axi_wlast;
  bit [S_COUNT-1:0]                        xbar_s_axi_wvalid;
  bit [S_COUNT-1:0]                        xbar_s_axi_bready;
  bit [S_COUNT-1:0][S_AXI_ID_WIDTH-1:0]    xbar_s_axi_arid;
  bit [S_COUNT-1:0][S_AXI_ADDR_WIDTH-1:0]  xbar_s_axi_araddr;
  bit [S_COUNT-1:0][7:0]                   xbar_s_axi_arlen;
  bit [S_COUNT-1:0][S_AXI_USER_WIDTH-1:0]  xbar_s_axi_aruser;
  bit [S_COUNT-1:0][2:0]                   xbar_s_axi_arsize;
  bit [S_COUNT-1:0][1:0]                   xbar_s_axi_arburst;
  bit [S_COUNT-1:0]                        xbar_s_axi_arlock;
  bit [S_COUNT-1:0][3:0]                   xbar_s_axi_arcache;
  bit [S_COUNT-1:0][2:0]                   xbar_s_axi_arprot;
  bit [S_COUNT-1:0]                        xbar_s_axi_arvalid;
  bit [S_COUNT-1:0]                        xbar_s_axi_rready;
  wire [S_COUNT-1:0]                       s_cpu_busy;

  for (genvar s=0; s<S_COUNT; s++) begin : s_mux
    wire cpu_busy = cpu_s_axi_busy[s];
    assign s_cpu_busy[s] = cpu_busy;

    assign s_axi_awid[s]     = cpu_busy ? cpu_s_axi_awid[s]     : xbar_s_axi_awid[s];
    assign s_axi_awaddr[s]   = cpu_busy ? cpu_s_axi_awaddr[s]   : xbar_s_axi_awaddr[s];
    assign s_axi_awlen[s]    = cpu_busy ? cpu_s_axi_awlen[s]    : xbar_s_axi_awlen[s];
    assign s_axi_awuser[s]   = cpu_busy ? cpu_s_axi_awuser[s]   : xbar_s_axi_awuser[s];
    assign s_axi_awsize[s]   = cpu_busy ? cpu_s_axi_awsize[s]   : xbar_s_axi_awsize[s];
    assign s_axi_awburst[s]  = cpu_busy ? cpu_s_axi_awburst[s]  : xbar_s_axi_awburst[s];
    assign s_axi_awlock[s]   = cpu_busy ? cpu_s_axi_awlock[s]   : xbar_s_axi_awlock[s];
    assign s_axi_awcache[s]  = cpu_busy ? cpu_s_axi_awcache[s]  : xbar_s_axi_awcache[s];
    assign s_axi_awprot[s]   = cpu_busy ? cpu_s_axi_awprot[s]   : xbar_s_axi_awprot[s];
    assign s_axi_awvalid[s]  = cpu_busy ? cpu_s_axi_awvalid[s]  : xbar_s_axi_awvalid[s];
    assign s_axi_wdata[s]    = cpu_busy ? cpu_s_axi_wdata[s]    : xbar_s_axi_wdata[s];
    assign s_axi_wstrb[s]    = cpu_busy ? cpu_s_axi_wstrb[s]    : xbar_s_axi_wstrb[s];
    assign s_axi_wlast[s]    = cpu_busy ? cpu_s_axi_wlast[s]    : xbar_s_axi_wlast[s];
    assign s_axi_wvalid[s]   = cpu_busy ? cpu_s_axi_wvalid[s]   : xbar_s_axi_wvalid[s];
    assign s_axi_bready[s]   = cpu_busy ? cpu_s_axi_bready[s]   : xbar_s_axi_bready[s];
    assign s_axi_arid[s]     = cpu_busy ? cpu_s_axi_arid[s]     : xbar_s_axi_arid[s];
    assign s_axi_araddr[s]   = cpu_busy ? cpu_s_axi_araddr[s]   : xbar_s_axi_araddr[s];
    assign s_axi_arlen[s]    = cpu_busy ? cpu_s_axi_arlen[s]    : xbar_s_axi_arlen[s];
    assign s_axi_aruser[s]   = cpu_busy ? cpu_s_axi_aruser[s]   : xbar_s_axi_aruser[s];
    assign s_axi_arsize[s]   = cpu_busy ? cpu_s_axi_arsize[s]   : xbar_s_axi_arsize[s];
    assign s_axi_arburst[s]  = cpu_busy ? cpu_s_axi_arburst[s]  : xbar_s_axi_arburst[s];
    assign s_axi_arlock[s]   = cpu_busy ? cpu_s_axi_arlock[s]   : xbar_s_axi_arlock[s];
    assign s_axi_arcache[s]  = cpu_busy ? cpu_s_axi_arcache[s]  : xbar_s_axi_arcache[s];
    assign s_axi_arprot[s]   = cpu_busy ? cpu_s_axi_arprot[s]   : xbar_s_axi_arprot[s];
    assign s_axi_arvalid[s]  = cpu_busy ? cpu_s_axi_arvalid[s]  : xbar_s_axi_arvalid[s];
    assign s_axi_rready[s]   = cpu_busy ? cpu_s_axi_rready[s]   : xbar_s_axi_rready[s];
  end

  task axi_write(input bit [S_AXI_ADDR_WIDTH-1:0] addr, input bit [S_AXI0_DATA_WIDTH-1:0] data);

    automatic int i = get_s_index(addr);
    automatic int wait_count;

    if (i < 0)
      $fatal(1, "FB_AXI: no S AXI target for write addr=0x%0h", addr);

    at_posedge_clk();
    `TIMESTEP;
    cpu_s_axi_busy [i] = 1;
    cpu_s_axi_awid   [i] = S_AXI_ID_WIDTH'(1);
    cpu_s_axi_awaddr [i] = addr;
    cpu_s_axi_awlen  [i] = 8'd0;
    cpu_s_axi_awuser [i] = S_AXI_USER_WIDTH'(S_AXI_USER_VALUE);
    cpu_s_axi_awsize [i] = 3'(S_SIZE);
    cpu_s_axi_awburst[i] = 2'b01;
    cpu_s_axi_awlock [i] = 0;
    cpu_s_axi_awcache[i] = 0;
    cpu_s_axi_awprot [i] = 0;
    cpu_s_axi_awvalid[i] = 1;

    wait_count = 0;
    do begin
      at_posedge_clk();
      `TIMESTEP;
      if (wait_count++ >= FB_AXI_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting AWREADY addr=0x%0h data=0x%0h awready=%0b",
               addr, data, s_axi_awready[i]);
    end while (!s_axi_awready[i]);

    cpu_s_axi_awvalid[i] = 0;
    cpu_s_axi_wdata  [i] = '0;
    cpu_s_axi_wdata  [i][S_AXI0_DATA_WIDTH-1:0] = data;
    cpu_s_axi_wstrb  [i] = '0;
    cpu_s_axi_wstrb  [i][S_BYTES-1:0] = {S_BYTES{1'b1}};
    cpu_s_axi_wlast  [i] = 1;
    cpu_s_axi_wvalid [i] = 1;

    wait_count = 0;
    do begin
      at_posedge_clk();
      `TIMESTEP;
      if (wait_count++ >= FB_AXI_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting WREADY addr=0x%0h data=0x%0h wready=%0b",
               addr, data, s_axi_wready[i]);
    end while (!s_axi_wready[i]);

    cpu_s_axi_wvalid [i] = 0;
    cpu_s_axi_bready [i] = 1;

    wait_count = 0;
    do begin
      at_posedge_clk();
      `TIMESTEP;
      if (wait_count++ >= FB_AXI_RESP_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting BVALID addr=0x%0h data=0x%0h", addr, data);
    end while (!s_axi_bvalid[i]);

    cpu_s_axi_bready[i] = 0;
    cpu_s_axi_wdata [i] = '0;
    cpu_s_axi_wstrb [i] = '0;
    cpu_s_axi_wlast [i] = '0;
    cpu_s_axi_busy  [i] = 0;
  endtask

  task axi_read(input bit [S_AXI_ADDR_WIDTH-1:0] addr, output bit [S_AXI0_DATA_WIDTH-1:0] rdata);

    automatic int i = get_s_index(addr);
    automatic int wait_count;

    if (i < 0)
      $fatal(1, "FB_AXI: no S AXI target for read addr=0x%0h", addr);

    at_posedge_clk();
    `TIMESTEP;
    cpu_s_axi_busy [i] = 1;
    cpu_s_axi_arid   [i] = S_AXI_ID_WIDTH'(1);
    cpu_s_axi_araddr [i] = addr;
    cpu_s_axi_arlen  [i] = 8'd0;
    cpu_s_axi_aruser [i] = S_AXI_USER_WIDTH'(S_AXI_USER_VALUE);
    cpu_s_axi_arsize [i] = 3'(S_SIZE);
    cpu_s_axi_arburst[i] = 2'b01;
    cpu_s_axi_arlock [i] = 0;
    cpu_s_axi_arcache[i] = 0;
    cpu_s_axi_arprot [i] = 0;
    cpu_s_axi_arvalid[i] = 1;

    wait_count = 0;
    while (!s_axi_arready[i]) begin
      if (wait_count++ >= FB_AXI_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting ARREADY addr=0x%0h arready=%0b",
               addr, s_axi_arready[i]);
      `TIMESTEP;
    end

    at_posedge_clk();
    `TIMESTEP;
    cpu_s_axi_arvalid[i] = 0;
    cpu_s_axi_rready [i] = 1;

    wait_count = 0;
    while (!s_axi_rvalid[i]) begin
      if (wait_count++ >= FB_AXI_RESP_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting RVALID addr=0x%0h", addr);
      `TIMESTEP;
    end

    `TIMESTEP;
    rdata = s_axi_rdata[i][S_AXI0_DATA_WIDTH-1:0];
    at_posedge_clk();
    `TIMESTEP;
    cpu_s_axi_rready[i] = 0;
    cpu_s_axi_busy  [i] = 0;
  endtask

  export "DPI-C" task fb_task_read_reg;
  export "DPI-C" function fb_fn_read_reg;
  export "DPI-C" task fb_task_write_reg;

  typedef bit [S_AXI0_DATA_WIDTH-1:0] fb_reg_t;
  typedef longint unsigned fb_reg_64_t;
  fb_reg_64_t tmp_get_data;

  task automatic fb_task_read_reg(input longint addr);
    fb_reg_t d;
    axi_read(S_AXI_ADDR_WIDTH'(addr), d);
    tmp_get_data = fb_reg_64_t'(d);
  endtask

  function automatic fb_reg_64_t fb_fn_read_reg();
    return tmp_get_data;
  endfunction

  task automatic fb_task_write_reg(input longint addr, input longint data);
    axi_write(S_AXI_ADDR_WIDTH'(addr), fb_reg_t'(data));
  endtask


  // Memory Congestion Emulation

  bit [M_COUNT-1:0] m_axi_arvalid_zipcpu;
  bit [M_COUNT-1:0] m_axi_arready_zipcpu;
  bit [M_COUNT-1:0] m_axi_rvalid_zipcpu;
  bit [M_COUNT-1:0] m_axi_rready_zipcpu;
  bit [M_COUNT-1:0] m_axi_awvalid_zipcpu;
  bit [M_COUNT-1:0] m_axi_awready_zipcpu;
  bit [M_COUNT-1:0] m_axi_wvalid_zipcpu;
  bit [M_COUNT-1:0] m_axi_wready_zipcpu;
  bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0] m_axi_bid_zipcpu;
  bit [M_COUNT-1:0][1:0] m_axi_bresp_zipcpu;
  bit [M_COUNT-1:0] m_axi_bvalid_zipcpu;
  bit [M_COUNT-1:0] m_axi_bready_zipcpu;
  bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0] m_axi_rid_zipcpu;
  bit [M_COUNT-1:0][M_AXI_DATA_WIDTH_MAX-1:0] m_axi_rdata_zipcpu;
  bit [M_COUNT-1:0][1:0] m_axi_rresp_zipcpu;
  bit [M_COUNT-1:0] m_axi_rlast_zipcpu;
  bit [M_COUNT-1:0] wr_route_valid;
  int wr_route_s [M_COUNT];
  int wr_resp_s [M_COUNT];
  bit [M_COUNT-1:0] rd_route_valid;
  int rd_route_s [M_COUNT];
  bit [M_AXI_ID_COUNT-1:0] wr_id_active [M_COUNT];
  int wr_id_target_s [M_COUNT][M_AXI_ID_COUNT];
  bit [M_AXI_ID_COUNT-1:0] rd_id_active [M_COUNT];
  int rd_id_target_s [M_COUNT][M_AXI_ID_COUNT];
  bit [M_COUNT-1:0] rand_ar;
  bit [M_COUNT-1:0] rand_r;
  bit [M_COUNT-1:0] rand_aw;
  bit [M_COUNT-1:0] rand_w;
  bit [M_COUNT-1:0] rand_b;
	  

	  // Handle M Masters
  import "DPI-C" context function int unsigned fb_c_read_ddr32_addr32  (input int unsigned addr, chandle p_mem);
  import "DPI-C" context function void         fb_c_write_ddr32_addr32 (input int unsigned addr, input int unsigned data, input byte unsigned strb, chandle p_mem);

  for (m=0; m< M_COUNT; m++) begin

	    always_ff @(posedge clk or negedge rstn) begin
	      if (!rstn) begin
	        rand_r [m]  <= 1;
	        rand_ar[m]  <= 1;
          rand_aw[m]  <= 1;
          rand_w [m]  <= 1;
          rand_b [m]  <= 1;
        end else begin
          rand_r  [m]  <= $urandom_range(0, 1000) < VALID_PROB;
          rand_ar [m]  <= $urandom_range(0, 1000) < VALID_PROB;
          rand_aw [m]  <= $urandom_range(0, 1000) < READY_PROB;
          rand_w  [m]  <= $urandom_range(0, 1000) < READY_PROB;
          rand_b  [m]  <= $urandom_range(0, 1000) < READY_PROB;
	      end
	    end

	    wire signed [31:0] aw_sel_s = get_s_index(m_axi_awaddr[m]);
	    wire signed [31:0] ar_sel_s = get_s_index(m_axi_araddr[m]);
	    wire aw_sel_ddr = aw_sel_s < 0;
	    wire ar_sel_ddr = ar_sel_s < 0;
	    wire aw_id_conflict = wr_id_active[m][m_axi_awid[m]] && (wr_id_target_s[m][m_axi_awid[m]] != aw_sel_s);
	    wire ar_id_conflict = rd_id_active[m][m_axi_arid[m]] && (rd_id_target_s[m][m_axi_arid[m]] != ar_sel_s);
	    wire aw_accept      = m_axi_awvalid[m] && m_axi_awready[m];
	    wire w_accept_last  = m_axi_wvalid[m] && m_axi_wready[m] && m_axi_wlast[m];
	    wire b_accept       = m_axi_bvalid[m] && m_axi_bready[m];
	    wire ar_accept      = m_axi_arvalid[m] && m_axi_arready[m];
	    wire r_accept_last  = m_axi_rvalid[m] && m_axi_rready[m] && m_axi_rlast[m];

	    always_ff @(posedge clk or negedge rstn) begin
	      if (!rstn) begin
	        wr_route_valid[m] <= 1'b0;
	        wr_route_s[m] <= -1;
	        wr_resp_s[m] <= -1;
	        rd_route_valid[m] <= 1'b0;
	        rd_route_s[m] <= -1;
	        wr_id_active[m] <= '0;
	        rd_id_active[m] <= '0;
	        for (int id=0; id<M_AXI_ID_COUNT; id++) begin
	          wr_id_target_s[m][id] <= -1;
	          rd_id_target_s[m][id] <= -1;
	        end
	      end else begin
	        if (aw_accept) begin
	          wr_route_valid[m] <= 1'b1;
	          wr_route_s[m] <= aw_sel_s;
	          wr_id_active[m][m_axi_awid[m]] <= 1'b1;
	          wr_id_target_s[m][m_axi_awid[m]] <= aw_sel_s;
	          if (!aw_sel_ddr && S_AXI_DATA_WIDTH[aw_sel_s] != M_AXI_DATA_WIDTH[m])
	            $fatal(1, "FB_AXI: write width conversion unsupported m%0d(%0d) -> s%0d(%0d)",
	                   m, M_AXI_DATA_WIDTH[m], aw_sel_s, S_AXI_DATA_WIDTH[aw_sel_s]);
	        end
	        if (w_accept_last) begin
	          wr_route_valid[m] <= 1'b0;
	          wr_resp_s[m] <= wr_route_s[m];
	        end
	        if (b_accept) begin
	          wr_id_active[m][m_axi_bid[m]] <= 1'b0;
	          wr_resp_s[m] <= -1;
	        end
	        if (ar_accept) begin
	          rd_route_valid[m] <= 1'b1;
	          rd_route_s[m] <= ar_sel_s;
	          rd_id_active[m][m_axi_arid[m]] <= 1'b1;
	          rd_id_target_s[m][m_axi_arid[m]] <= ar_sel_s;
	          if (!ar_sel_ddr && S_AXI_DATA_WIDTH[ar_sel_s] != M_AXI_DATA_WIDTH[m])
	            $fatal(1, "FB_AXI: read width conversion unsupported m%0d(%0d) -> s%0d(%0d)",
	                   m, M_AXI_DATA_WIDTH[m], ar_sel_s, S_AXI_DATA_WIDTH[ar_sel_s]);
	        end
	        if (r_accept_last) begin
	          rd_route_valid[m] <= 1'b0;
	          rd_id_active[m][m_axi_rid[m]] <= 1'b0;
	          rd_route_s[m] <= -1;
	        end
	      end
	    end

	    assign m_axi_awvalid_zipcpu[m] = rand_aw[m] && m_axi_awvalid[m] &&  aw_sel_ddr && !aw_id_conflict && !wr_route_valid[m];
	    assign m_axi_awready[m]        = rand_aw[m] && !aw_id_conflict && !wr_route_valid[m] &&
	                                     (aw_sel_ddr ? m_axi_awready_zipcpu[m] : s_axi_awready[aw_sel_s]) &&
	                                     (!s_cpu_busy[aw_sel_s] || aw_sel_ddr);

	    assign m_axi_wvalid_zipcpu[m] = rand_w[m] && m_axi_wvalid[m] && wr_route_valid[m] && wr_route_s[m] < 0;
	    assign m_axi_wready[m]        = rand_w[m] && wr_route_valid[m] &&
	                                    (wr_route_s[m] < 0 ? m_axi_wready_zipcpu[m] : s_axi_wready[wr_route_s[m]]) &&
	                                    (wr_route_s[m] < 0 || !s_cpu_busy[wr_route_s[m]]);

	    assign m_axi_bvalid[m]        = rand_b[m] && (wr_resp_s[m] < 0 ? m_axi_bvalid_zipcpu[m] : s_axi_bvalid[wr_resp_s[m]]);
	    assign m_axi_bid[m]           = wr_resp_s[m] < 0 ? m_axi_bid_zipcpu[m] : M_AXI_ID_WIDTH'(s_axi_bid[wr_resp_s[m]]);
	    assign m_axi_bresp[m]         = wr_resp_s[m] < 0 ? m_axi_bresp_zipcpu[m] : s_axi_bresp[wr_resp_s[m]];
	    assign m_axi_bready_zipcpu[m] = rand_b[m] && m_axi_bready[m] && wr_resp_s[m] < 0;

	    assign m_axi_arvalid_zipcpu[m] = rand_ar[m] && m_axi_arvalid[m] &&  ar_sel_ddr && !ar_id_conflict && !rd_route_valid[m];
	    assign m_axi_arready[m]        = rand_ar[m] && !ar_id_conflict && !rd_route_valid[m] &&
	                                     (ar_sel_ddr ? m_axi_arready_zipcpu[m] : s_axi_arready[ar_sel_s]) &&
	                                     (!s_cpu_busy[ar_sel_s] || ar_sel_ddr);

	    assign m_axi_rvalid[m]        = rand_r[m] && rd_route_valid[m] &&
	                                    (rd_route_s[m] < 0 ? m_axi_rvalid_zipcpu[m] : s_axi_rvalid[rd_route_s[m]]);
	    assign m_axi_rid[m]           = rd_route_s[m] < 0 ? m_axi_rid_zipcpu[m] : M_AXI_ID_WIDTH'(s_axi_rid[rd_route_s[m]]);
	    assign m_axi_rdata[m]         = rd_route_s[m] < 0 ? m_axi_rdata_zipcpu[m] : s_axi_rdata[rd_route_s[m]];
	    assign m_axi_rresp[m]         = rd_route_s[m] < 0 ? m_axi_rresp_zipcpu[m] : s_axi_rresp[rd_route_s[m]];
	    assign m_axi_rlast[m]         = rd_route_s[m] < 0 ? m_axi_rlast_zipcpu[m] : s_axi_rlast[rd_route_s[m]];
	    assign m_axi_rready_zipcpu[m] = rand_r[m] && m_axi_rready[m] && rd_route_valid[m] && rd_route_s[m] < 0;

	    for (genvar s=0; s<S_COUNT; s++) begin : m_to_s
	      assign xbar_s_axi_awid[s]    = S_AXI_ID_WIDTH'(m_axi_awid[m]);
	      assign xbar_s_axi_awaddr[s]  = S_AXI_ADDR_WIDTH'(m_axi_awaddr[m]);
	      assign xbar_s_axi_awlen[s]   = m_axi_awlen[m];
	      assign xbar_s_axi_awuser[s]  = '0;
	      assign xbar_s_axi_awsize[s]  = m_axi_awsize[m];
	      assign xbar_s_axi_awburst[s] = m_axi_awburst[m];
	      assign xbar_s_axi_awlock[s]  = m_axi_awlock[m];
	      assign xbar_s_axi_awcache[s] = m_axi_awcache[m];
	      assign xbar_s_axi_awprot[s]  = m_axi_awprot[m];
	      assign xbar_s_axi_awvalid[s] = rand_aw[m] && m_axi_awvalid[m] && !aw_sel_ddr &&
	                                     aw_sel_s == s && !aw_id_conflict && !wr_route_valid[m] &&
	                                     !s_cpu_busy[s];
	      assign xbar_s_axi_wdata[s]   = m_axi_wdata[m];
	      assign xbar_s_axi_wstrb[s]   = m_axi_wstrb[m];
	      assign xbar_s_axi_wlast[s]   = m_axi_wlast[m];
	      assign xbar_s_axi_wvalid[s]  = rand_w[m] && m_axi_wvalid[m] && wr_route_valid[m] &&
	                                     wr_route_s[m] == s && !s_cpu_busy[s];
	      assign xbar_s_axi_bready[s]  = rand_b[m] && m_axi_bready[m] && wr_resp_s[m] == s;
	      assign xbar_s_axi_arid[s]    = S_AXI_ID_WIDTH'(m_axi_arid[m]);
	      assign xbar_s_axi_araddr[s]  = S_AXI_ADDR_WIDTH'(m_axi_araddr[m]);
	      assign xbar_s_axi_arlen[s]   = m_axi_arlen[m];
	      assign xbar_s_axi_aruser[s]  = '0;
	      assign xbar_s_axi_arsize[s]  = m_axi_arsize[m];
	      assign xbar_s_axi_arburst[s] = m_axi_arburst[m];
	      assign xbar_s_axi_arlock[s]  = m_axi_arlock[m];
	      assign xbar_s_axi_arcache[s] = m_axi_arcache[m];
	      assign xbar_s_axi_arprot[s]  = m_axi_arprot[m];
	      assign xbar_s_axi_arvalid[s] = rand_ar[m] && m_axi_arvalid[m] && !ar_sel_ddr &&
	                                     ar_sel_s == s && !ar_id_conflict && !rd_route_valid[m] &&
	                                     !s_cpu_busy[s];
	      assign xbar_s_axi_rready[s]  = rand_r[m] && m_axi_rready[m] && rd_route_valid[m] &&
	                                     rd_route_s[m] == s;
	    end

	    zipcpu_axi2ram #(
      .C_S_AXI_ID_WIDTH   (M_AXI_ID_WIDTH  ),
      .C_S_AXI_DATA_WIDTH (M_AXI_DATA_WIDTH_MAX),
      .C_S_AXI_ADDR_WIDTH (M_AXI_ADDR_WIDTH),
      .OPT_LOCK           (OPT_LOCK        ),
      .OPT_LOCKID         (OPT_LOCKID      ),
      .OPT_LOWPOWER       (OPT_LOWPOWER    )
    ) zip_axi2ram (

      .o_we      (wen   [m]),
      .o_waddr   (waddr [m]),
      .o_wdata   (wdata [m]),
      .o_wstrb   (wstrb [m]),
      .o_rd      (ren   [m]),
      .o_raddr   (raddr [m]),
      .i_rdata   (rdata [m]),

      .S_AXI_ACLK   (clk),
      .S_AXI_ARESETN(rstn),

      .S_AXI_AWID   (m_axi_awid           [m]),
      .S_AXI_AWADDR (m_axi_awaddr         [m]),
      .S_AXI_AWLEN  (m_axi_awlen          [m]),
      .S_AXI_AWSIZE (m_axi_awsize         [m]),
      .S_AXI_AWBURST(m_axi_awburst        [m]),
      .S_AXI_AWLOCK (m_axi_awlock         [m]),
      .S_AXI_AWCACHE(m_axi_awcache        [m]),
      .S_AXI_AWPROT (m_axi_awprot         [m]),
      .S_AXI_AWQOS  (),
      .S_AXI_AWVALID(m_axi_awvalid_zipcpu [m]),
      .S_AXI_AWREADY(m_axi_awready_zipcpu [m]),
      .S_AXI_WDATA  (m_axi_wdata          [m]),
      .S_AXI_WSTRB  (m_axi_wstrb          [m]),
      .S_AXI_WLAST  (m_axi_wlast          [m]),
      .S_AXI_WVALID (m_axi_wvalid_zipcpu  [m]),
      .S_AXI_WREADY (m_axi_wready_zipcpu  [m]),
      .S_AXI_BID    (m_axi_bid_zipcpu     [m]),
      .S_AXI_BRESP  (m_axi_bresp_zipcpu   [m]),
      .S_AXI_BVALID (m_axi_bvalid_zipcpu  [m]),
      .S_AXI_BREADY (m_axi_bready_zipcpu  [m]),
      .S_AXI_ARID   (m_axi_arid           [m]),
      .S_AXI_ARADDR (m_axi_araddr         [m]),
      .S_AXI_ARLEN  (m_axi_arlen          [m]),
      .S_AXI_ARSIZE (m_axi_arsize         [m]),
      .S_AXI_ARBURST(m_axi_arburst        [m]),
      .S_AXI_ARLOCK (m_axi_arlock         [m]),
      .S_AXI_ARCACHE(m_axi_arcache        [m]),
      .S_AXI_ARPROT (m_axi_arprot         [m]),
      .S_AXI_ARQOS(),
      .S_AXI_ARVALID(m_axi_arvalid_zipcpu [m]),
      .S_AXI_ARREADY(m_axi_arready_zipcpu [m]),
      .S_AXI_RID    (m_axi_rid_zipcpu     [m]),
      .S_AXI_RDATA  (m_axi_rdata_zipcpu   [m]),
      .S_AXI_RRESP  (m_axi_rresp_zipcpu   [m]),
      .S_AXI_RLAST  (m_axi_rlast_zipcpu   [m]),
      .S_AXI_RVALID (m_axi_rvalid_zipcpu  [m]),
      .S_AXI_RREADY (m_axi_rready_zipcpu  [m])
    );

    // DDR Read & Write

    byte tmp_byte;
    bit [M_AXI_DATA_WIDTH_MAX-1:0] tmp_data;

    always_ff @(posedge clk or negedge rstn) begin
      if (!rstn) begin
        tmp_data <= '0;
        rdata <= '0;
      end else begin
        if (ren[m]) begin
          for (int i = 0; i < M_AXI_DATA_WIDTH_MAX/32; i++) begin
            tmp_data[i*32 +: 32] = fb_c_read_ddr32_addr32((32'(raddr[m]) << LSB) + 4*i, p_mem);
          end
          rdata[m] <= tmp_data;
        end
        if (wen[m])
          for (int i = 0; i < M_AXI_DATA_WIDTH_MAX/32; i++)
            fb_c_write_ddr32_addr32((32'(waddr[m]) << LSB) + 4*i, wdata[m][i*32 +: 32], 8'(wstrb[m][i*4 +: 4]), p_mem);
      end
      end
  end


  // Simulation

`ifdef VERILATOR
  `define AUTOMATIC
`elsif XCELIUM
  `define AUTOMATIC
`else
  `define AUTOMATIC automatic
`endif

  import "DPI-C" context task `AUTOMATIC run_sim(input chandle p_mem);
  import "DPI-C" context function chandle fb_get_mem_p ();

  initial begin
    firebridge_done = 0;
    wait (rstn);
    p_mem = fb_get_mem_p();
    run_sim(p_mem);
    firebridge_done = 1;
  end

endmodule
