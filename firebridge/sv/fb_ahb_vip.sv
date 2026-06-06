`timescale 1ns/1ps

module fb_ahb_vip #(
  parameter int AHB_ADDR_WIDTH = 32,
  parameter int AHB_DATA_WIDTH = 32,
  parameter int FB_AHB_TIMEOUT = 100000
)(
  input  bit                         clk,
  input  bit                         rstn,
  output bit                         firebridge_done,

  output bit                         hsel,
  output bit [AHB_ADDR_WIDTH-1:0]    haddr,
  output bit [AHB_DATA_WIDTH-1:0]    hwdata,
  output bit                         hwrite,
  output bit [2:0]                   hsize,
  output bit [1:0]                   htrans,
  output bit                         hready,
  input  bit                         hreadyout,
  input  bit                         hresp,
  input  bit [AHB_DATA_WIDTH-1:0]    hrdata
);
  localparam bit [1:0] AHB_HTRANS_IDLE   = 2'b00;
  localparam bit [1:0] AHB_HTRANS_NONSEQ = 2'b10;
  localparam bit [2:0] AHB_HSIZE_WORD    = 3'b010;

  typedef bit [AHB_DATA_WIDTH-1:0] fb_reg_t;
  typedef longint unsigned fb_reg_64_t;

  fb_reg_64_t tmp_get_data;
  chandle p_mem;

`ifndef CALIPTRA_FB_AHB
  // Standalone mode (selfcheck/sha256): this VIP owns the clock-step DPI,
  // run_sim, and the timing-based register tasks. In combined Caliptra Mode B
  // (CALIPTRA_FB_AHB) fb_axi_vip owns those; here we keep only the bus-driving
  // export functions further below.
`ifdef VERILATOR
  function byte get_clk();
    get_clk = 8'(clk);
  endfunction
  export "DPI-C" function get_clk;

  import "DPI-C" context function void at_posedge_clk();
  import "DPI-C" context function void step_time_veri();

  `define TIMESTEP step_time_veri()
`else
  task at_posedge_clk();
    @(posedge clk) #10ps;
  endtask

  `define TIMESTEP #10ps
`endif

  task automatic wait_hreadyout(input string opname, input bit [AHB_ADDR_WIDTH-1:0] addr);
    int wait_count;
    wait_count = 0;
    while (!hreadyout) begin
      if (wait_count++ >= FB_AHB_TIMEOUT)
        $fatal(1, "FB_AHB: timeout waiting HREADYOUT during %s addr=0x%0h", opname, addr);
      `TIMESTEP;
    end
    if (hresp)
      $fatal(1, "FB_AHB: HRESP error during %s addr=0x%0h", opname, addr);
  endtask

  task automatic ahb_idle();
    hsel   = 1'b0;
    haddr  = '0;
    hwdata = '0;
    hwrite = 1'b0;
    hsize  = AHB_HSIZE_WORD;
    htrans = AHB_HTRANS_IDLE;
    hready = 1'b1;
  endtask

  task automatic ahb_write(input bit [AHB_ADDR_WIDTH-1:0] addr, input fb_reg_t data);
    at_posedge_clk();
    `TIMESTEP;
    hsel   = 1'b1;
    haddr  = addr;
    hwrite = 1'b1;
    hsize  = AHB_HSIZE_WORD;
    htrans = AHB_HTRANS_NONSEQ;
    hready = 1'b1;

    at_posedge_clk();
    `TIMESTEP;
    haddr  = '0;
    hwdata = data;
    hwrite = 1'b0;
    htrans = AHB_HTRANS_IDLE;

    wait_hreadyout("write", addr);

    at_posedge_clk();
    `TIMESTEP;
    ahb_idle();
  endtask

  task automatic ahb_read(input bit [AHB_ADDR_WIDTH-1:0] addr, output fb_reg_t data);
    at_posedge_clk();
    `TIMESTEP;
    hsel   = 1'b1;
    haddr  = addr;
    hwrite = 1'b0;
    hsize  = AHB_HSIZE_WORD;
    htrans = AHB_HTRANS_NONSEQ;
    hready = 1'b1;

    at_posedge_clk();
    `TIMESTEP;
    haddr  = '0;
    hwdata = '0;
    htrans = AHB_HTRANS_IDLE;

    wait_hreadyout("read", addr);
    `TIMESTEP;
    data = hrdata;

    at_posedge_clk();
    `TIMESTEP;
    ahb_idle();
  endtask

  export "DPI-C" task fb_task_read_reg;
  export "DPI-C" function fb_fn_read_reg;
  export "DPI-C" task fb_task_write_reg;

  // Workaround: inline ahb_write / ahb_read here.  When these bodies live
  // in a sub-task that has DPI imports, signal assignments between the DPI
  // import calls are silently dropped by the tool's DPI-export codegen.
  task automatic fb_task_write_reg(input longint addr, input longint data);
    at_posedge_clk();
    `TIMESTEP;
    hsel   = 1'b1;
    haddr  = AHB_ADDR_WIDTH'(addr);
    hwrite = 1'b1;
    hsize  = AHB_HSIZE_WORD;
    htrans = AHB_HTRANS_NONSEQ;
    hready = 1'b1;

    at_posedge_clk();
    `TIMESTEP;
    haddr  = '0;
    hwdata = fb_reg_t'(data);
    hwrite = 1'b0;
    htrans = AHB_HTRANS_IDLE;

    wait_hreadyout("write", AHB_ADDR_WIDTH'(addr));

    at_posedge_clk();
    `TIMESTEP;
    ahb_idle();
  endtask

  task automatic fb_task_read_reg(input longint addr);
    at_posedge_clk();
    `TIMESTEP;
    hsel   = 1'b1;
    haddr  = AHB_ADDR_WIDTH'(addr);
    hwrite = 1'b0;
    hsize  = AHB_HSIZE_WORD;
    htrans = AHB_HTRANS_NONSEQ;
    hready = 1'b1;

    at_posedge_clk();
    `TIMESTEP;
    haddr  = '0;
    hwdata = '0;
    htrans = AHB_HTRANS_IDLE;

    wait_hreadyout("read", AHB_ADDR_WIDTH'(addr));
    `TIMESTEP;
    tmp_get_data = fb_reg_64_t'(hrdata);

    at_posedge_clk();
    `TIMESTEP;
    ahb_idle();
  endtask

  function automatic fb_reg_64_t fb_fn_read_reg();
    return tmp_get_data;
  endfunction
`endif  // !CALIPTRA_FB_AHB

  // Workaround for Verilator 5.044 bug: signal assignments between DPI import
  // calls inside DPI export *tasks* are silently dropped from generated code.
  // DPI export *functions* (no timing semantics) are generated correctly.
  // So we expose bus-driving as functions and implement the protocol in C.
  // hwdata_v is 64-bit so the same export works for the 32-bit standalone bus
  // and the 64-bit Caliptra internal AHB (C side does any lane placement).
  function automatic void fb_ahb_drive(
      input byte unsigned     hsel_v,
      input int  unsigned     haddr_v,
      input longint unsigned  hwdata_v,
      input byte unsigned     hwrite_v,
      input byte unsigned     hsize_v,
      input byte unsigned     htrans_v,
      input byte unsigned     hready_v
  );
    hsel   = hsel_v[0];
    haddr  = AHB_ADDR_WIDTH'(haddr_v);
    hwdata = AHB_DATA_WIDTH'(hwdata_v);
    hwrite = hwrite_v[0];
    hsize  = hsize_v[2:0];
    htrans = htrans_v[1:0];
    hready = hready_v[0];
  endfunction
  export "DPI-C" function fb_ahb_drive;

  function automatic byte unsigned fb_ahb_hreadyout();
    return {7'b0, hreadyout};
  endfunction
  export "DPI-C" function fb_ahb_hreadyout;

  function automatic byte unsigned fb_ahb_hresp();
    return {7'b0, hresp};
  endfunction
  export "DPI-C" function fb_ahb_hresp;

  function automatic longint unsigned fb_ahb_hrdata();
    return 64'(hrdata);
  endfunction
  export "DPI-C" function fb_ahb_hrdata;

`ifndef CALIPTRA_FB_AHB
`ifdef VERILATOR
  `define AUTOMATIC
`elsif XCELIUM
  `define AUTOMATIC
`elsif VCS
  `define AUTOMATIC
`else
  `define AUTOMATIC automatic
`endif

  import "DPI-C" context task `AUTOMATIC run_sim(input chandle p_mem);
  import "DPI-C" context function chandle fb_get_mem_p();

  initial begin
    firebridge_done = 1'b0;
    ahb_idle();
    wait (rstn);
    p_mem = fb_get_mem_p();
    run_sim(p_mem);
    firebridge_done = 1'b1;
  end
`else
  // AHB-only Mode B: fb_ahb_vip owns clock/run_sim; tb soc_bfm handles SoC boot.
`ifdef VERILATOR
  function byte get_clk();
    get_clk = 8'(clk);
  endfunction
  export "DPI-C" function get_clk;
  import "DPI-C" context function void at_posedge_clk();
  import "DPI-C" context function void step_time_veri();
`else
  task at_posedge_clk();
    @(posedge clk) #10ps;
  endtask
  export "DPI-C" task at_posedge_clk;
  task step_time_veri();
    #1;
  endtask
  export "DPI-C" task step_time_veri;
`endif

`ifdef VERILATOR
  `define AUTOMATIC
`elsif XCELIUM
  `define AUTOMATIC
`elsif VCS
  `define AUTOMATIC
`else
  `define AUTOMATIC automatic
`endif

  import "DPI-C" context task `AUTOMATIC run_sim(input chandle p_mem);
  import "DPI-C" context function chandle fb_get_mem_p();

  initial begin
    firebridge_done = 1'b0;
    hsel   = 1'b0;
    haddr  = '0;
    hwdata = '0;
    hwrite = 1'b0;
    hsize  = AHB_HSIZE_WORD;
    htrans = AHB_HTRANS_IDLE;
    hready = 1'b1;
    wait (rstn);
    p_mem = fb_get_mem_p();
    run_sim(p_mem);
    firebridge_done = 1'b1;
  end
`endif
endmodule
