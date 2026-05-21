SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

USR          := $(shell id -un)
UID          := $(shell id -u)
GID          := $(shell id -g)
HOSTNAME_VAR := $(shell bash -lc 'echo $${USER:0:3}')

IMAGE     := caliptra-ubuntu
CONTAINER := caliptra-$(USR)

SYNOPSYS_ROOT := /tools/Syncopsys
VCS_HOME      := /tools/Synopsys/vcs/T-2022.06-SP2-10
SNPSLMD_LIC   := 1705@its-flexlm-lnx4.ucsd.edu
VERILATOR_VERSION ?= v5.044

HOST_REPO := $(CURDIR)
HOST_WS   := $(HOST_REPO)/ws
CONT_WS   := /home/usr/ws
CONT_HOME := /home/usr

X11_MOUNT := $(if $(wildcard /tmp/.X11-unix),-v /tmp/.X11-unix:/tmp/.X11-unix)
WSLG_MOUNT := $(if $(wildcard /mnt/wslg),-v /mnt/wslg:/mnt/wslg)
XAUTH_MOUNT := $(if $(wildcard $(HOME)/.Xauthority),-e XAUTHORITY=$(CONT_HOME)/.Xauthority -v $(HOME)/.Xauthority:$(CONT_HOME)/.Xauthority)
VCS_MOUNT := -v $(SYNOPSYS_ROOT):/tools/Synopsys:ro

.PHONY: fresh restart image build start enter kill submodules

fresh: kill image start

restart: kill start

build: image

image: submodules
	docker build \
		-f Dockerfile \
		--build-arg UID=$(UID) \
		--build-arg GID=$(GID) \
		--build-arg USERNAME=$(USR) \
		--build-arg VCS_HOME=$(VCS_HOME) \
		--build-arg SNPSLMD_LICENSE_FILE=$(SNPSLMD_LIC) \
		--build-arg VERILATOR_VERSION=$(VERILATOR_VERSION) \
		-t $(IMAGE) .

submodules:
	@if [ -d ws/usr/caliptra-rtl/.git ] || [ -f ws/usr/caliptra-rtl/.git ]; then \
		git -C ws/usr/caliptra-rtl submodule update --init --recursive; \
	else \
		git submodule update --init --recursive; \
	fi

start:
	- xhost +Local:docker
	docker run -d --name $(CONTAINER) \
		-h $(HOSTNAME_VAR) \
		-e DISPLAY=$(DISPLAY) \
		-e WAYLAND_DISPLAY=$(WAYLAND_DISPLAY) \
		-e VCS_HOME=$(VCS_HOME) \
		-e SNPSLMD_LICENSE_FILE=$(SNPSLMD_LIC) \
		--tty --interactive \
		$(XAUTH_MOUNT) \
		$(X11_MOUNT) \
		$(WSLG_MOUNT) \
		$(VCS_MOUNT) \
		-v $(HOST_WS):$(CONT_WS) \
		-w $(CONT_WS) \
		$(IMAGE) tail -f /dev/null

enter:
	docker exec -it $(CONTAINER) bash -i

kill:
	- docker kill $(CONTAINER) || true
	- docker rm $(CONTAINER) || true
