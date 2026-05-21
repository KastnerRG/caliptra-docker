# Docker for Caliptra RTL Simulation with VCS

This repository provides a Docker-based environment for running Caliptra RTL simulations using Synopsys VCS. It simplifies setup and ensures consistency across different systems.

## Features

- Ubuntu-based image for running the VCS/Verilator simulation environment.
- Pre-requisites for VCS
- Pre-built RISC-V toolchain (cross compiler, multilib, zicsr/zifencei extensions)
- Source-built Verilator, configurable via `VERILATOR_VERSION` and defaulting to v5.044.
- Caliptra RTL submodule pinned to upstream stable tag v2.1.2.

## Pre-requisites
- Set the variables: `SYNOPSYS_ROOT`, `VCS_HOME` and `SNPSLMD_LIC` in `Makefile`.
- Pull all submodules correctly:
```sh
git submodule update --init --recursive
git submodule update --recursive
```

## Working with Docker

```sh
make fresh
make enter

make restart
```

## Caliptra RTL

Caliptra workspace should look like this:
```plaintext
ws/
├── Makefile
├── usr/
│   └── caliptra-rtl # Repo listed below (fork of caliptra-rtl)
├── work/
    └── $(test)_$(sim)/
        └── ...
```
[Caliptra RTL upstream](https://github.com/chipsalliance/caliptra-rtl/tree/v2.1.2) pinned to stable tag v2.1.2.

## Run Simulation

Inside the docker container (in `ws` folder)

```sh
make list # Print a list of tests
make test=<test> sim=vcs
make test=<test> sim=verilator
```

eg. tests:
* hello_world_iccm
* hello_world_vcs
* smoke_test_sha256
* smoke_test_veer
* smoke_test_aes_gcm

## Key Files

* top RTL: `src/riscv_core/veer_el2/rtl/el2_veer_wrapper.sv`
* top TB: `src/integration/tb/caliptra_top_tb.sv`
* SoC IFC: `src/soc_ifc/rtl/soc_ifc_top.sv`
* Software `(c): src/integration/test_suites/${test}`
* Include dirs: `src/integration/config/caliptra_top_tb.vf`

How tests are loaded:

* `$(CALIPTRA_ROOT)/tools/scripts/Makefile test=$(test)`
* This generates:
  * `program.hex` - the primary program image 
  * `iccm.hex` - data to preload into the ICCM (Instruction Closely Coupled Memory) inside the core subsystem.
  * `dccm.hex` - data to preload into the DCCM (Data Closely Coupled Memory).
  * `mailbox.hex` - contents for the mailbox SRAM.
* Testbench loads them

<!-- 
Vivado xsim command to compile aes:
xsc usr/caliptra-rtl/src/integration/test_suites/libs/aes/aes.c --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/test_suites/includes/" --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/rtl" --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/test_suites/libs/printf/" --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/test_suites/libs/riscv_hw_if/"
```
 -->
