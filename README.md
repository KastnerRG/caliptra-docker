# Docker for Caliptra RTL Simulation with VCS

This repository provides a Docker-based environment for running Caliptra RTL simulations using Synopsys VCS. It simplifies setup and ensures consistency across different systems.

## Features

- CentOS 7.3-based, adding mirrors to avoid yum issues caused by EOL.
- Pre-requisites for VCS
- Pre-built RISC-V toolchain (cross compiler, multilib, zicsr/zifencei extensions)

## Steps

- Build the docker image using Docker compose.
```sh
docker compose build
```
- Start and enter the docker
```sh
source start_container.sh
```

## Pre-requisites
- Launch the volume of Caliptra workspace with RTL and scripts as described [here](https://github.com/zhenghuama/caliptra-sim-scripts)
- Set the correct path to VCS in `docker-compose.yml`
- Set the correct path to VCS and Synopsys licensing server in Dockerfile (`VCS_HOME` and `NPSLMD_LICENSE_FILE`).


