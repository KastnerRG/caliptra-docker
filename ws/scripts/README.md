# Setup Guide

## Caliptra RTL
Caliptra workspace should look like this:
```plaintext
ws/
├── usr/
│   └── caliptra-rtl # Repo listed below
├── sim_dir_1/
│   └── ...
├── sim_dir_2/
│   └── ...
└── scripts/  # this repo
    ├── helloworld_vcs.sh
    ├── iccm_lock_vcs.sh
    └── ...
```
[Caliptra RTL dev repo](https://github.com/zhenghuama/caliptra-rtl/tree/dev-v2.0) on branch dev-v2.0 (forked from Caliptra v2.0 stable release).

## VCS Docker
Docker repo here. To build the docker image:
```sh
docker compose build
```
To spin up the docker container and enter:
```sh
./start_container.sh
```

## Run Simulation
Inside the docker container, simply source the .sh files of this repo to run the simulation.