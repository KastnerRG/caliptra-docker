`timescale 1ns/1ps

// Minimal reproduction of the Mode-B dual-VIP scope problem:
//   module_a  = owns run_sim (like fb_axi_vip)
//   module_b  = exposes a bus-drive export function (like fb_ahb_vip)
// C run_sim (executing in module_a's DPI scope) must reach module_b's
// drive_val / read_val export functions via svSetScope.

module module_a(input bit clk, input bit rstn, output bit done);
  import "DPI-C" context task run_sim();
  initial begin
    done = 1'b0;
    wait (rstn);
    run_sim();
    done = 1'b1;
  end
endmodule

module module_b(output bit [31:0] val);
  function automatic void drive_val(input int unsigned v);
    val = v;
  endfunction
  export "DPI-C" function drive_val;

  function automatic int unsigned read_val();
    return val;
  endfunction
  export "DPI-C" function read_val;
endmodule

module scope_repro_tb;
  bit clk;
  initial clk = 1'b0;
  always #5ns clk = ~clk;

  bit rstn;
  initial begin
    rstn = 1'b0;
    repeat (5) @(posedge clk);
    rstn = 1'b1;
  end

  bit        done;
  bit [31:0] val;

  module_a a_i (.clk, .rstn, .done);
  module_b b_i (.val);

  initial begin
    wait (done);
    if (val == 32'hdeadbeef)
      $display("SCOPE_REPRO PASS val=0x%08x", val);
    else
      $display("SCOPE_REPRO FAIL val=0x%08x", val);
    $finish;
  end
endmodule
