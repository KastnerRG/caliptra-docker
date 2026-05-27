#include "Vscope_repro_tb.h"
#include "verilated.h"

static VerilatedContext *contextp = nullptr;
static Vscope_repro_tb *tb = nullptr;

int main(int argc, char **argv) {
  contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);
  tb = new Vscope_repro_tb{contextp};
  tb->eval();
  while (!contextp->gotFinish()) {
    tb->eval();
    contextp->timeInc(5);
  }
  delete tb;
  delete contextp;
  return 0;
}
