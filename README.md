# Docker for Caliptra RTL Simulation with VCS

This repository provides a Docker-based environment for running Caliptra RTL simulations using Synopsys VCS. It simplifies setup and ensures consistency across different systems.

## Features

- CentOS 7.3-based, adding mirrors to avoid yum issues caused by EOL.
- Pre-requisites for VCS
- Pre-built RISC-V toolchain (cross compiler, multilib, zicsr/zifencei extensions)

## Pre-requisites
- Set the correct path to VCS in `docker-compose.yml`
- Set the correct path to VCS and Synopsys licensing server in Dockerfile (`VCS_HOME` and `NPSLMD_LICENSE_FILE`).
- Pull all submodules correctly:
```
git submodule update --init --recursive
git submodule update --recursive
```

## Steps to start the container

- Build the docker image using Docker compose.
```sh
docker compose build
```
- Start your own container named `caliptra-$USERNAME` and enter
```sh
source start_container.sh
```
- Kill the container (if anything goes wrong)
```sh
source kill_container.sh
```

## Run Simulations

```
cd ws
source scripts/helloworld_vcs.sh
source scripts/iccm_lock_vcs.sh
source ./scripts/sha256_vcs.sh
```


