# Docker for Caliptra RTL Simulation with VCS

This repository provides a Docker-based environment for running Caliptra RTL simulations using Synopsys VCS. It simplifies setup and ensures consistency across different systems.

## Features

- CentOS 7.3-based, adding mirrors to avoid yum issues caused by EOL.
- Pre-requisites for VCS
- Pre-built RISC-V toolchain (cross compiler, multilib, zicsr/zifencei extensions)

## Pre-requisites
- Set the variables: `SYNOPSYS_ROOT`, `VCS_HOME` and `SNPSLMD_LIC` in `Makefile`.
- Pull all submodules correctly:
```sh
git submodule update --init --recursive
git submodule update --recursive
```

## Working with Docker

```sh
make build
make start
make enter
make kill
```

## Caliptra RTL
Caliptra workspace should look like this:
```plaintext
ws/
├── usr/
│   └── caliptra-rtl # Repo listed below (fork of caliptra-rtl)
├── work-vcs/
│   └── ...
├── work-verilator/
    └── ...
```
[Caliptra RTL dev repo](https://github.com/zhenghuama/caliptra-rtl/tree/dev-v2.0) on branch dev-v2.0 (forked from Caliptra v2.0 stable release).

## Run Simulation

Inside the docker container (in `ws` folder)

```sh
make test= sim=
```

test:
* hello_world_iccm
* hello_world_vcs
* smoke_test_sha256
* smoke_test_veer
* smoke_test_aes_gcm

sim:
* vcs
* verilator

## Xsim AES

Not sure what this is:

```
xsc usr/caliptra-rtl/src/integration/test_suites/libs/aes/aes.c --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/test_suites/includes/" --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/rtl" --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/test_suites/libs/printf/" --gcc_compile_options "-Iusr/caliptra-rtl/src/integration/test_suites/libs/riscv_hw_if/"
```