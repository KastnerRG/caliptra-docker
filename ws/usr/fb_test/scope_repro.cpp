#include "svdpi.h"
#include <cstdio>

extern "C" void drive_val(unsigned int v);
extern "C" unsigned int read_val();

extern "C" void run_sim() {
  // run_sim runs in module_a's scope. module_b's export functions live in a
  // different scope, so we must locate and switch to it before calling them.
  const char *candidates[] = {
      "TOP.scope_repro_tb.b_i",
      "scope_repro_tb.b_i",
      "TOP.scope_repro_tb",
  };
  svScope b = nullptr;
  for (const char *name : candidates) {
    svScope s = svGetScopeFromName(name);
    std::fprintf(stderr, "  svGetScopeFromName(\"%s\") = %p\n", name, (void *)s);
    if (s && !b) b = s;
  }
  if (!b) {
    std::fprintf(stderr, "run_sim: could not find module_b scope\n");
    return;
  }
  svSetScope(b);
  drive_val(0xdeadbeefu);
  std::fprintf(stderr, "run_sim: read_val() = 0x%08x\n", read_val());
}
