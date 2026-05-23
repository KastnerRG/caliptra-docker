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

  task automatic fb_task_read_reg(input longint addr);
    fb_reg_t d;
    ahb_read(AHB_ADDR_WIDTH'(addr), d);
    tmp_get_data = fb_reg_64_t'(d);
  endtask

  function automatic fb_reg_64_t fb_fn_read_reg();
    return tmp_get_data;
  endfunction

  task automatic fb_task_write_reg(input longint addr, input longint data);
    ahb_write(AHB_ADDR_WIDTH'(addr), fb_reg_t'(data));
  endtask

`ifdef VERILATOR
  `define AUTOMATIC
`elsif XCELIUM
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
endmodule
