#include "Vsha256_ahb_tb.h"
#include "verilated.h"

static VerilatedContext *contextp = nullptr;
static Vsha256_ahb_tb *tb = nullptr;

extern "C" unsigned char get_clk();

extern "C" void step_time_veri() {
  tb->eval();
  contextp->timeInc(5);
}

extern "C" void at_posedge_clk() {
  while (true) {
    unsigned char before = get_clk();
    step_time_veri();
    if (before == 0 && get_clk() == 1) break;
  }
}

int main(int argc, char **argv) {
  contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);
  tb = new Vsha256_ahb_tb{contextp};
  tb->eval();
  while (!contextp->gotFinish()) {
    step_time_veri();
  }
  delete tb;
  delete contextp;
  return 0;
}
