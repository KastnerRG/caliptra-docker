`timescale 1ns/1ps

/*
TODO:
* I dont want fifo specific ports, address and decoding.
* Change S_AXI_BASE_ADDR to AXI_BASE_ADDR, maybe add AXI_REGION_BYTES
* Consider there is only one address map: all slaves and masters
* If you get a req through the M port, you have to route it to the S port based on the address map.
* If its in the DDR region, then we use the fb_c_functions
* Outside this module, connect the fifo to an m port, such that traffic to the fifo's region gets routed to the FIFO, without treating fifo as a special case. I want to solve the general case.
* AXI out of order transaction is a problem.
  - if we get a req in the s port, put the {id, m_idx} in a queue (SV data structure)., and route the req. pop it when the response comes back.
  - if we get another req with same id, but different m_idx, we have to stall accepting requests until that {id, m_idx} leaves the queue.
* If you think there is a non trivial problem with this, stop and tell me asap.
*/

module fb_axi_vip #(
  parameter
  S_COUNT          = 1,
  M_COUNT          = 1,

  M_AXI_DATA_WIDTH  = 128,
  M_AXI_ADDR_WIDTH  = 32,
  M_AXI_ID_WIDTH    = 6,
  M_AXI_STRB_WIDTH  = (M_AXI_DATA_WIDTH/8),
  S_AXI_DATA_WIDTH  = 32,
  S_AXI_ID_WIDTH    = 6,
  S_AXI_ADDR_WIDTH  = 40,
  S_AXI_USER_WIDTH  = 32,
  S_AXI_USER_VALUE  = 32'h0,
  S_AXI_STRB_WIDTH  = (S_AXI_DATA_WIDTH/8),
  S_AXI_BASE_ADDR   = {32'hA0000000},
  M_AXI_FIFO_BASE_ADDR = 32'hFA570000,
  M_AXI_FIFO_ADDR_WIDTH = 18,

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
  output bit [S_COUNT-1:0][S_AXI_DATA_WIDTH-1:0]  s_axi_wdata  ,
  output bit [S_COUNT-1:0][S_AXI_STRB_WIDTH-1:0]  s_axi_wstrb  ,
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
  input  bit [S_COUNT-1:0][S_AXI_DATA_WIDTH-1:0]  s_axi_rdata  ,
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
  input  bit [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0]  m_axi_wdata  ,
  input  bit [M_COUNT-1:0][M_AXI_STRB_WIDTH-1:0]  m_axi_wstrb  ,
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
  output bit [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0]  m_axi_rdata  ,
	  output bit [M_COUNT-1:0][1:0]                   m_axi_rresp  ,
	  output bit [M_COUNT-1:0]                        m_axi_rlast  ,
	  output bit [M_COUNT-1:0]                        m_axi_rvalid ,
	  input  bit [M_COUNT-1:0]                        m_axi_rready ,

	  // Optional decoded FIFO AXI slave target for DMA-side traffic.
	  output bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    f_axi_awid   ,
	  output bit [M_COUNT-1:0][M_AXI_ADDR_WIDTH-1:0]  f_axi_awaddr ,
	  output bit [M_COUNT-1:0][7:0]                   f_axi_awlen  ,
	  output bit [M_COUNT-1:0][2:0]                   f_axi_awsize ,
	  output bit [M_COUNT-1:0][1:0]                   f_axi_awburst,
	  output bit [M_COUNT-1:0]                        f_axi_awlock ,
	  output bit [M_COUNT-1:0][3:0]                   f_axi_awcache,
	  output bit [M_COUNT-1:0][2:0]                   f_axi_awprot ,
	  output bit [M_COUNT-1:0]                        f_axi_awvalid,
	  input  bit [M_COUNT-1:0]                        f_axi_awready,
	  output bit [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0]  f_axi_wdata  ,
	  output bit [M_COUNT-1:0][M_AXI_STRB_WIDTH-1:0]  f_axi_wstrb  ,
	  output bit [M_COUNT-1:0]                        f_axi_wlast  ,
	  output bit [M_COUNT-1:0]                        f_axi_wvalid ,
	  input  bit [M_COUNT-1:0]                        f_axi_wready ,
	  input  bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    f_axi_bid    ,
	  input  bit [M_COUNT-1:0][1:0]                   f_axi_bresp  ,
	  input  bit [M_COUNT-1:0]                        f_axi_bvalid ,
	  output bit [M_COUNT-1:0]                        f_axi_bready ,
	  output bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    f_axi_arid   ,
	  output bit [M_COUNT-1:0][M_AXI_ADDR_WIDTH-1:0]  f_axi_araddr ,
	  output bit [M_COUNT-1:0][7:0]                   f_axi_arlen  ,
	  output bit [M_COUNT-1:0][2:0]                   f_axi_arsize ,
	  output bit [M_COUNT-1:0][1:0]                   f_axi_arburst,
	  output bit [M_COUNT-1:0]                        f_axi_arlock ,
	  output bit [M_COUNT-1:0][3:0]                   f_axi_arcache,
	  output bit [M_COUNT-1:0][2:0]                   f_axi_arprot ,
	  output bit [M_COUNT-1:0]                        f_axi_arvalid,
	  input  bit [M_COUNT-1:0]                        f_axi_arready,
	  input  bit [M_COUNT-1:0][M_AXI_ID_WIDTH-1:0]    f_axi_rid    ,
	  input  bit [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0]  f_axi_rdata  ,
	  input  bit [M_COUNT-1:0][1:0]                   f_axi_rresp  ,
	  input  bit [M_COUNT-1:0]                        f_axi_rlast  ,
	  input  bit [M_COUNT-1:0]                        f_axi_rvalid ,
	  output bit [M_COUNT-1:0]                        f_axi_rready
	);
  chandle p_mem;
  genvar m;
  localparam  
	    LSB = $clog2(M_AXI_DATA_WIDTH)-3,
		    OPT_LOCK          = 1'b0,
		    OPT_LOCKID        = 1'b1,
		    OPT_LOWPOWER      = 1'b0,
		    FB_AXI_TIMEOUT    = 100000,
		    FB_AXI_RESP_TIMEOUT = 10000000,
		    S_BYTES           = (S_AXI_DATA_WIDTH/8),
		    S_SIZE            = $clog2(S_BYTES),
		    M_AXI_ID_COUNT    = (1 << M_AXI_ID_WIDTH);

  bit  [M_COUNT-1:0]                            ren;
  bit  [M_COUNT-1:0][M_AXI_ADDR_WIDTH-LSB-1:0]  raddr;
  bit  [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0]      rdata;
	  bit  [M_COUNT-1:0]                            wen;
	  bit  [M_COUNT-1:0][M_AXI_ADDR_WIDTH-LSB-1:0]  waddr;
	  bit  [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0]      wdata;
	  bit  [M_COUNT-1:0][M_AXI_DATA_WIDTH/8-1:0]    wstrb;

	  function automatic bit is_m_fifo_addr(input bit [M_AXI_ADDR_WIDTH-1:0] addr);
	    bit [M_AXI_ADDR_WIDTH-1:0] fifo_mask;
	    fifo_mask = {M_AXI_ADDR_WIDTH{1'b1}} << M_AXI_FIFO_ADDR_WIDTH;
	    return (addr & fifo_mask) == (M_AXI_ADDR_WIDTH'(M_AXI_FIFO_BASE_ADDR) & fifo_mask);
	  endfunction

  function automatic int get_s_index(int addr);
    int index = -1;
    if (/* verilator lint_off UNSIGNED */ addr >= S_AXI_BASE_ADDR[S_COUNT-1])
      index = S_COUNT-1;
    else for (int s=0; s < S_COUNT-1; s++)
      if (/* verilator lint_off UNSIGNED */ addr >= S_AXI_BASE_ADDR[s] && addr < S_AXI_BASE_ADDR[s+1]) begin
        index = s;
        break;
      end
    return index;
  endfunction

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

  task axi_write(input bit [S_AXI_ADDR_WIDTH-1:0] addr, input bit [S_AXI_DATA_WIDTH-1:0] data);

    automatic int i = get_s_index(addr);
    automatic int wait_count;

    at_posedge_clk();
    `TIMESTEP;
    s_axi_awid   [i] = S_AXI_ID_WIDTH'(1);
    s_axi_awaddr [i] = addr;
    s_axi_awlen  [i] = 8'd0;
    s_axi_awuser [i] = S_AXI_USER_WIDTH'(S_AXI_USER_VALUE);
    s_axi_awsize [i] = 3'(S_SIZE);
    s_axi_awburst[i] = 2'b01;
    s_axi_awlock [i] = 0;
    s_axi_awcache[i] = 0;
    s_axi_awprot [i] = 0;
    s_axi_awvalid[i] = 1;

    wait_count = 0;
    do begin
      at_posedge_clk();
      `TIMESTEP;
      if (wait_count++ >= FB_AXI_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting AWREADY addr=0x%0h data=0x%0h awready=%0b",
               addr, data, s_axi_awready[i]);
    end while (!s_axi_awready[i]);

    s_axi_awvalid[i] = 0;
    s_axi_wdata  [i] = data;
    s_axi_wstrb  [i] = {S_AXI_STRB_WIDTH{1'b1}};
    s_axi_wlast  [i] = 1;
    s_axi_wvalid [i] = 1;

    wait_count = 0;
    do begin
      at_posedge_clk();
      `TIMESTEP;
      if (wait_count++ >= FB_AXI_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting WREADY addr=0x%0h data=0x%0h wready=%0b",
               addr, data, s_axi_wready[i]);
    end while (!s_axi_wready[i]);

    s_axi_wvalid [i] = 0;
    s_axi_bready [i] = 1;

    wait_count = 0;
    do begin
      at_posedge_clk();
      `TIMESTEP;
      if (wait_count++ >= FB_AXI_RESP_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting BVALID addr=0x%0h data=0x%0h", addr, data);
    end while (!s_axi_bvalid[i]);

    s_axi_bready[i] = 0;
    s_axi_wdata [i] = '0;
    s_axi_wstrb [i] = '0;
    s_axi_wlast [i] = '0;
  endtask

  task axi_read(input bit [S_AXI_ADDR_WIDTH-1:0] addr, output bit [S_AXI_DATA_WIDTH-1:0] rdata);

    automatic int i = get_s_index(addr);
    automatic int wait_count;

    at_posedge_clk();
    s_axi_arid   [i] = S_AXI_ID_WIDTH'(1);
    s_axi_araddr [i] = addr;
    s_axi_arlen  [i] = 8'd0;
    s_axi_aruser [i] = S_AXI_USER_WIDTH'(S_AXI_USER_VALUE);
    s_axi_arsize [i] = 3'(S_SIZE);
    s_axi_arburst[i] = 2'b01;
    s_axi_arlock [i] = 0;
    s_axi_arcache[i] = 0;
    s_axi_arprot [i] = 0;
    s_axi_arvalid[i] = 1;

    wait_count = 0;
    while (!s_axi_arready[i]) begin
      if (wait_count++ >= FB_AXI_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting ARREADY addr=0x%0h arready=%0b",
               addr, s_axi_arready[i]);
      `TIMESTEP;
    end

    at_posedge_clk();
    `TIMESTEP;
    s_axi_arvalid[i] = 0;
    s_axi_rready [i] = 1;

    wait_count = 0;
    while (!s_axi_rvalid[i]) begin
      if (wait_count++ >= FB_AXI_RESP_TIMEOUT)
        $fatal(1, "FB_AXI: timeout waiting RVALID addr=0x%0h", addr);
      `TIMESTEP;
    end

    `TIMESTEP;
    rdata = s_axi_rdata[i];
    at_posedge_clk();
    `TIMESTEP;
    s_axi_rready[i] = 0;
  endtask

  export "DPI-C" task fb_task_read_reg;
  export "DPI-C" function fb_fn_read_reg;
  export "DPI-C" task fb_task_write_reg;

  typedef bit [S_AXI_DATA_WIDTH-1:0] fb_reg_t;
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
	  bit [M_COUNT-1:0][M_AXI_DATA_WIDTH-1:0] m_axi_rdata_zipcpu;
	  bit [M_COUNT-1:0][1:0] m_axi_rresp_zipcpu;
	  bit [M_COUNT-1:0] m_axi_rlast_zipcpu;
	  bit [M_COUNT-1:0] wr_route_valid;
	  bit [M_COUNT-1:0] wr_route_fifo;
	  bit [M_COUNT-1:0] rd_route_valid;
	  bit [M_COUNT-1:0] rd_route_fifo;
	  bit [M_AXI_ID_COUNT-1:0] wr_id_active [M_COUNT];
	  bit [M_AXI_ID_COUNT-1:0] wr_id_target_fifo [M_COUNT];
	  bit [M_AXI_ID_COUNT-1:0] rd_id_active [M_COUNT];
	  bit [M_AXI_ID_COUNT-1:0] rd_id_target_fifo [M_COUNT];
	  bit [M_COUNT-1:0] rand_ar;
	  bit [M_COUNT-1:0] rand_r;
	  bit [M_COUNT-1:0] rand_aw;
	  bit [M_COUNT-1:0] rand_w;
	  bit [M_COUNT-1:0] rand_b;
	  

	  // Handle M Masters
  import "DPI-C" context function byte fb_c_read_ddr8_addr32  (input int unsigned addr, chandle p_mem);
  import "DPI-C" context function void fb_c_write_ddr8_addr32 (input int unsigned addr, input byte data, chandle p_mem);

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

	    wire aw_sel_fifo    = is_m_fifo_addr(m_axi_awaddr[m]);
	    wire ar_sel_fifo    = is_m_fifo_addr(m_axi_araddr[m]);
	    wire aw_id_conflict = wr_id_active[m][m_axi_awid[m]] && (wr_id_target_fifo[m][m_axi_awid[m]] != aw_sel_fifo);
	    wire ar_id_conflict = rd_id_active[m][m_axi_arid[m]] && (rd_id_target_fifo[m][m_axi_arid[m]] != ar_sel_fifo);
	    wire aw_accept      = m_axi_awvalid[m] && m_axi_awready[m];
	    wire w_accept_last  = m_axi_wvalid[m] && m_axi_wready[m] && m_axi_wlast[m];
	    wire b_accept       = m_axi_bvalid[m] && m_axi_bready[m];
	    wire ar_accept      = m_axi_arvalid[m] && m_axi_arready[m];
	    wire r_accept_last  = m_axi_rvalid[m] && m_axi_rready[m] && m_axi_rlast[m];

	    always_ff @(posedge clk or negedge rstn) begin
	      if (!rstn) begin
	        wr_route_valid[m] <= 1'b0;
	        wr_route_fifo[m]  <= 1'b0;
	        rd_route_valid[m] <= 1'b0;
	        rd_route_fifo[m]  <= 1'b0;
	        wr_id_active[m] <= '0;
	        wr_id_target_fifo[m] <= '0;
	        rd_id_active[m] <= '0;
	        rd_id_target_fifo[m] <= '0;
	      end else begin
	        if (aw_accept) begin
	          wr_route_valid[m] <= 1'b1;
	          wr_route_fifo[m]  <= aw_sel_fifo;
	          wr_id_active[m][m_axi_awid[m]] <= 1'b1;
	          wr_id_target_fifo[m][m_axi_awid[m]] <= aw_sel_fifo;
	        end
	        if (w_accept_last) begin
	          wr_route_valid[m] <= 1'b0;
	        end
	        if (b_accept) begin
	          wr_id_active[m][m_axi_bid[m]] <= 1'b0;
	        end
	        if (ar_accept) begin
	          rd_route_valid[m] <= 1'b1;
	          rd_route_fifo[m]  <= ar_sel_fifo;
	          rd_id_active[m][m_axi_arid[m]] <= 1'b1;
	          rd_id_target_fifo[m][m_axi_arid[m]] <= ar_sel_fifo;
	        end
	        if (r_accept_last) begin
	          rd_route_valid[m] <= 1'b0;
	          rd_id_active[m][m_axi_rid[m]] <= 1'b0;
	        end
	      end
	    end

	    assign m_axi_awvalid_zipcpu[m] = rand_aw[m] && m_axi_awvalid[m] && !aw_sel_fifo && !aw_id_conflict && !wr_route_valid[m];
	    assign f_axi_awvalid[m]        = rand_aw[m] && m_axi_awvalid[m] &&  aw_sel_fifo && !aw_id_conflict && !wr_route_valid[m];
	    assign m_axi_awready[m]        = rand_aw[m] && !aw_id_conflict && !wr_route_valid[m] &&
	                                     (aw_sel_fifo ? f_axi_awready[m] : m_axi_awready_zipcpu[m]);

	    assign m_axi_wvalid_zipcpu[m] = rand_w[m] && m_axi_wvalid[m] && wr_route_valid[m] && !wr_route_fifo[m];
	    assign f_axi_wvalid[m]        = rand_w[m] && m_axi_wvalid[m] && wr_route_valid[m] &&  wr_route_fifo[m];
	    assign m_axi_wready[m]        = rand_w[m] && wr_route_valid[m] &&
	                                    (wr_route_fifo[m] ? f_axi_wready[m] : m_axi_wready_zipcpu[m]);

	    assign m_axi_bvalid[m]        = rand_b[m] && (m_axi_bvalid_zipcpu[m] || f_axi_bvalid[m]);
	    assign m_axi_bid[m]           = f_axi_bvalid[m] ? f_axi_bid[m] : m_axi_bid_zipcpu[m];
	    assign m_axi_bresp[m]         = f_axi_bvalid[m] ? f_axi_bresp[m] : m_axi_bresp_zipcpu[m];
	    assign m_axi_bready_zipcpu[m] = rand_b[m] && m_axi_bready[m] && m_axi_bvalid_zipcpu[m] && !f_axi_bvalid[m];
	    assign f_axi_bready[m]        = rand_b[m] && m_axi_bready[m] && f_axi_bvalid[m];

	    assign m_axi_arvalid_zipcpu[m] = rand_ar[m] && m_axi_arvalid[m] && !ar_sel_fifo && !ar_id_conflict && !rd_route_valid[m];
	    assign f_axi_arvalid[m]        = rand_ar[m] && m_axi_arvalid[m] &&  ar_sel_fifo && !ar_id_conflict && !rd_route_valid[m];
	    assign m_axi_arready[m]        = rand_ar[m] && !ar_id_conflict && !rd_route_valid[m] &&
	                                     (ar_sel_fifo ? f_axi_arready[m] : m_axi_arready_zipcpu[m]);

	    assign m_axi_rvalid[m]        = rand_r[m] && rd_route_valid[m] &&
	                                    (rd_route_fifo[m] ? f_axi_rvalid[m] : m_axi_rvalid_zipcpu[m]);
	    assign m_axi_rid[m]           = rd_route_fifo[m] ? f_axi_rid[m] : m_axi_rid_zipcpu[m];
	    assign m_axi_rdata[m]         = rd_route_fifo[m] ? f_axi_rdata[m] : m_axi_rdata_zipcpu[m];
	    assign m_axi_rresp[m]         = rd_route_fifo[m] ? f_axi_rresp[m] : m_axi_rresp_zipcpu[m];
	    assign m_axi_rlast[m]         = rd_route_fifo[m] ? f_axi_rlast[m] : m_axi_rlast_zipcpu[m];
	    assign m_axi_rready_zipcpu[m] = rand_r[m] && m_axi_rready[m] && rd_route_valid[m] && !rd_route_fifo[m];
	    assign f_axi_rready[m]        = rand_r[m] && m_axi_rready[m] && rd_route_valid[m] &&  rd_route_fifo[m];

	    assign f_axi_awid[m]    = m_axi_awid[m];
	    assign f_axi_awaddr[m]  = m_axi_awaddr[m];
	    assign f_axi_awlen[m]   = m_axi_awlen[m];
	    assign f_axi_awsize[m]  = m_axi_awsize[m];
	    assign f_axi_awburst[m] = m_axi_awburst[m];
	    assign f_axi_awlock[m]  = m_axi_awlock[m];
	    assign f_axi_awcache[m] = m_axi_awcache[m];
	    assign f_axi_awprot[m]  = m_axi_awprot[m];
	    assign f_axi_wdata[m]   = m_axi_wdata[m];
	    assign f_axi_wstrb[m]   = m_axi_wstrb[m];
	    assign f_axi_wlast[m]   = m_axi_wlast[m];
	    assign f_axi_arid[m]    = m_axi_arid[m];
	    assign f_axi_araddr[m]  = m_axi_araddr[m];
	    assign f_axi_arlen[m]   = m_axi_arlen[m];
	    assign f_axi_arsize[m]  = m_axi_arsize[m];
	    assign f_axi_arburst[m] = m_axi_arburst[m];
	    assign f_axi_arlock[m]  = m_axi_arlock[m];
	    assign f_axi_arcache[m] = m_axi_arcache[m];
	    assign f_axi_arprot[m]  = m_axi_arprot[m];

	    zipcpu_axi2ram #(
      .C_S_AXI_ID_WIDTH   (M_AXI_ID_WIDTH  ),
      .C_S_AXI_DATA_WIDTH (M_AXI_DATA_WIDTH),
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
    bit [M_AXI_DATA_WIDTH-1:0] tmp_data;

    always_ff @(posedge clk or negedge rstn) begin
      if (!rstn) begin
        tmp_data <= '0;
        rdata <= '0;
      end else begin
        if (ren[m]) begin
          for (int i = 0; i < M_AXI_DATA_WIDTH/8; i++) begin
            tmp_data[i*8 +: 8] = fb_c_read_ddr8_addr32((32'(raddr[m]) << LSB) + i, p_mem);
          end
          rdata[m] <= tmp_data;
        end
        if (wen[m]) 
          for (int i = 0; i < M_AXI_DATA_WIDTH/8; i++) 
            if (wstrb[m][i]) 
              fb_c_write_ddr8_addr32((32'(waddr[m]) << LSB) + i, wdata[m][i*8 +: 8], p_mem);
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
