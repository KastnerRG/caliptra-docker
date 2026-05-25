`timescale 1ns/1ps

module ahb_wait_mem #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int WAIT_CYCLES = 2
)(
  input  logic                  hclk,
  input  logic                  hreset_n,
  input  logic                  hsel_i,
  input  logic [ADDR_WIDTH-1:0] haddr_i,
  input  logic [DATA_WIDTH-1:0] hwdata_i,
  input  logic                  hwrite_i,
  input  logic [2:0]            hsize_i,
  input  logic                  hready_i,
  input  logic [1:0]            htrans_i,
  output logic                  hresp_o,
  output logic                  hreadyout_o,
  output logic [DATA_WIDTH-1:0] hrdata_o
);
  logic [DATA_WIDTH-1:0] mem [0:255];
  logic [ADDR_WIDTH-1:0] latched_addr;
  logic                  latched_write;
  logic                  pending;
  int                    wait_count;

  assign hresp_o = 1'b0;

  always_ff @(posedge hclk or negedge hreset_n) begin
    if (!hreset_n) begin
      hreadyout_o   <= 1'b1;
      hrdata_o      <= '0;
      latched_addr  <= '0;
      latched_write <= 1'b0;
      pending       <= 1'b0;
      wait_count    <= 0;
    end else begin
      if (pending) begin
        if (wait_count == 0) begin
          hreadyout_o <= 1'b1;
          if (latched_write)
            mem[latched_addr[9:2]] <= hwdata_i;
          else
            hrdata_o <= mem[latched_addr[9:2]];
          pending <= 1'b0;
        end else begin
          wait_count <= wait_count - 1;
        end
      end else if (hsel_i && hready_i && htrans_i[1]) begin
        latched_addr  <= haddr_i;
        latched_write <= hwrite_i;
        pending       <= 1'b1;
        wait_count    <= WAIT_CYCLES;
        hreadyout_o   <= (WAIT_CYCLES == 0);
        if (WAIT_CYCLES == 0) begin
          if (hwrite_i)
            mem[haddr_i[9:2]] <= hwdata_i;
          else
            hrdata_o <= mem[haddr_i[9:2]];
          pending <= 1'b0;
        end
      end
    end
  end
endmodule

module ahb_selfcheck_tb;
  // Internal clock — matches fb_top_verilator_wrap.cpp pattern where step_time_veri()
  // only calls eval()+timeInc() without toggling a clock pin.
  bit clk;
  initial clk = 1'b0;
  always #5ns clk = ~clk;
  bit rstn;
  bit firebridge_done;
  bit hsel;
  bit [31:0] haddr;
  bit [31:0] hwdata;
  bit hwrite;
  bit [2:0] hsize;
  bit [1:0] htrans;
  bit hready;
  bit hreadyout;
  bit hresp;
  bit [31:0] hrdata;

  initial begin
    rstn = 1'b0;
    repeat (5) @(posedge clk);
    rstn = 1'b1;
  end

  fb_ahb_vip fb_ahb_i (
    .clk,
    .rstn,
    .firebridge_done,
    .hsel,
    .haddr,
    .hwdata,
    .hwrite,
    .hsize,
    .htrans,
    .hready,
    .hreadyout,
    .hresp,
    .hrdata
  );

  ahb_wait_mem mem_i (
    .hclk(clk),
    .hreset_n(rstn),
    .hsel_i(hsel),
    .haddr_i(haddr),
    .hwdata_i(hwdata),
    .hwrite_i(hwrite),
    .hsize_i(hsize),
    .hready_i(hready),
    .htrans_i(htrans),
    .hresp_o(hresp),
    .hreadyout_o(hreadyout),
    .hrdata_o(hrdata)
  );

  initial begin
    wait (firebridge_done);
    $display("FB_AHB selfcheck PASS");
    $finish;
  end
endmodule
