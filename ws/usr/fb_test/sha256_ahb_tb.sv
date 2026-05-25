`timescale 1ns/1ps

// AHB-only integration test: FireBridge AHB master drives a real Caliptra
// crypto block (sha256_ctrl) directly over AHB-Lite. No VeeR, no interrupts.
// The C firmware (run_sim in sha256_ahb_fw.cpp) programs SHA256("abc") and
// self-checks the digest.
module sha256_ahb_tb;
  bit clk;
  initial clk = 1'b0;
  always #5ns clk = ~clk;

  bit rstn;
  bit firebridge_done;

  bit        hsel;
  bit [31:0] haddr;
  bit [31:0] hwdata;
  bit        hwrite;
  bit [2:0]  hsize;
  bit [1:0]  htrans;
  bit        hready;
  bit        hreadyout;
  bit        hresp;
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

  sha256_ctrl #(
    .AHB_DATA_WIDTH(32),
    .AHB_ADDR_WIDTH(32)
  ) dut (
    .clk        (clk),
    .reset_n    (rstn),
    .cptra_pwrgood(rstn),
    .haddr_i    (haddr),
    .hwdata_i   (hwdata),
    .hsel_i     (hsel),
    .hwrite_i   (hwrite),
    .hready_i   (hready),
    .htrans_i   (htrans),
    .hsize_i    (hsize),
    .hresp_o    (hresp),
    .hreadyout_o(hreadyout),
    .hrdata_o   (hrdata),
    .error_intr (),
    .notif_intr (),
    .debugUnlock_or_scan_mode_switch(1'b0)
  );

  initial begin
    wait (firebridge_done);
    $display("FB_AHB sha256 PASS");
    $finish;
  end
endmodule
