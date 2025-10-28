SHELL := /bin/bash
.PHONY: start build kill enter

USR          := $(shell id -un)
UID          := $(shell id -u)
GID          := $(shell id -g)
HOSTNAME_VAR := $(shell bash -lc 'echo $${USER:2:3}')
IMAGE        := $(USR)/vcs-caliptra-centos:dev
CONTAINER    := caliptra-$(USR)

build:
	- xhost +Local:docker
	docker build \
		-f Dockerfile \
		--build-arg UID=$(UID) \
		--build-arg GID=$(GID) \
		--build-arg USERNAME=$(USR) \
		-t $(IMAGE) .

start:
	- xhost +Local:docker
	docker run -d --name $(CONTAINER) \
		-h $(HOSTNAME_VAR) \
		-e DISPLAY=$$DISPLAY \
		--tty --interactive \
		-v /tmp/.X11-unix:/tmp/.X11-unix \
		-v ./ws:/home/usr/ws \
		-v /tools/Syncopsys:/tools/Synopsys:ro \
		-w /home/usr/ws \
		$(IMAGE) tail -f /dev/null

enter:
	docker exec -it $(CONTAINER) bash

kill:
	docker kill $(CONTAINER) || true
	docker rm   $(CONTAINER) || true
