#include "Vahb_selfcheck_tb.h"
#include "verilated.h"

vluint64_t main_time = 0;
Vahb_selfcheck_tb *tb = nullptr;

double sc_time_stamp() {
  return main_time;
}

extern "C" unsigned char get_clk();

extern "C" void step_time_veri() {
  Verilated::timeInc(1);
  main_time += 1;
  if (main_time % 5 == 0) {
    tb->clk = !tb->clk;
  }
  tb->eval();
}

extern "C" void at_posedge_clk() {
  unsigned char prev_clk = get_clk();
  while (true) {
    step_time_veri();
    if (prev_clk == 0 && get_clk() == 1) {
      step_time_veri();
      break;
    }
    prev_clk = get_clk();
  }
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  tb = new Vahb_selfcheck_tb;
  tb->clk = 0;
  while (!Verilated::gotFinish()) {
    step_time_veri();
  }
  delete tb;
  return 0;
}
