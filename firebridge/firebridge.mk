################################################################################
# firebridge.mk — FireBridge build & speedup targets for Caliptra
#
# Include in caliptra-docker/Makefile.  All targets run inside the Docker
# container via "docker exec caliptra-aba bash -lc '...'" or directly when
# CONT_MK_ROOT is set.
#
# Variables (all overridable on the command line):
#   TEST          - Caliptra test name (default: smoke_test_sha256)
#   FB            - 1 = FireBridge mode (FB_HAL=1), 0 = stock VeeR (default: 0)
#   FROM_SCRATCH  - 1 = delete build dir before building (default: 0)
#   SIM           - verilator|vcs (default: verilator)
#   FB_FW_LIB_SRCS - extra firmware libs (default auto-detected from test name)
#   FB_FW_LIB_DIRS - directories for FB_FW_LIB_SRCS
#   FB_FW_CFLAGS   - extra C flags for firmware (e.g. -DCALIPTRA_INTERNAL_TRNG)
################################################################################

# Container-side paths (set by Dockerfile ENV)
CONT_CALIPTRA_ROOT ?= /home/usr/ws/caliptra-rtl
CONT_CALIPTRA_WS   ?= /home/usr/ws
CONT_MK             = $(CONT_CALIPTRA_ROOT)/tools/scripts/Makefile

# Host-side workspace (used by docker exec targets below)
CONTAINER          ?= caliptra-$(shell id -un)

TEST          ?= smoke_test_sha256
FB            ?= 0
FROM_SCRATCH  ?= 0
SIM           ?= verilator

# Build directory names separate FB from no-FB and prevent clobbering
ifeq ($(FB),1)
_BD_SUFFIX = _fb
else
_BD_SUFFIX = _nofb
endif

WORK_DIR       = $(CONT_CALIPTRA_WS)/work/$(TEST)$(_BD_SUFFIX)
HOST_WORK_DIR  = $(HOST_WS)/work/$(TEST)$(_BD_SUFFIX)

################################################################################
# _fb_docker_run — run a shell fragment inside the running container
################################################################################
define _fb_docker_run
	docker exec $(CONTAINER) bash -lc '$(1)'
endef

################################################################################
# build — compile (and link) one test, with or without FB
################################################################################
.PHONY: build
build:
ifeq ($(FROM_SCRATCH),1)
	$(call _fb_docker_run, rm -rf $(WORK_DIR))
endif
	$(call _fb_docker_run, mkdir -p $(WORK_DIR) && \
	  make -C $(WORK_DIR) -f $(CONT_MK) \
	    CALIPTRA_ROOT=$(CONT_CALIPTRA_ROOT) \
	    CALIPTRA_WORKSPACE=$(CONT_CALIPTRA_WS) \
	    TESTNAME=$(TEST) FB=$(FB) \
	    $(if $(FB_FW_LIB_SRCS),FB_FW_LIB_SRCS="$(FB_FW_LIB_SRCS)") \
	    $(if $(FB_FW_LIB_DIRS),FB_FW_LIB_DIRS="$(FB_FW_LIB_DIRS)") \
	    $(if $(FB_FW_CFLAGS),FB_FW_CFLAGS="$(FB_FW_CFLAGS)") \
	    $(SIM)-build 2>&1 | tail -20)

################################################################################
# run — run the simulation binary for one test (builds first if needed)
################################################################################
.PHONY: run
run: build
	$(call _fb_docker_run, cd $(WORK_DIR) && \
	  make -f $(CONT_MK) \
	    CALIPTRA_ROOT=$(CONT_CALIPTRA_ROOT) \
	    CALIPTRA_WORKSPACE=$(CONT_CALIPTRA_WS) \
	    TESTNAME=$(TEST) FB=$(FB) $(SIM))

################################################################################
# time_test — build + run BOTH no-FB (VeeR) and FB, measure wall-clock times.
#
# Usage examples:
#   make time_test TEST=smoke_test_sha256
#   make time_test TEST=smoke_test_hmac FB_FW_LIB_SRCS=".../hmac.c"
#
# Output: prints "nofb_time fb_time speedup" and writes a one-line CSV to
#         experiments/runs/speedup_<TEST>_<timestamp>.csv
################################################################################
.PHONY: time_test
time_test:
	$(call _fb_docker_run, \
	  NOFB_DIR=$(CONT_CALIPTRA_WS)/work/$(TEST)_nofb; \
	  FB_DIR=$(CONT_CALIPTRA_WS)/work/$(TEST)_fb; \
	  mkdir -p $$NOFB_DIR $$FB_DIR; \
	  BASE_MK="make -f $(CONT_MK) CALIPTRA_ROOT=$(CONT_CALIPTRA_ROOT) CALIPTRA_WORKSPACE=$(CONT_CALIPTRA_WS) TESTNAME=$(TEST)"; \
	  echo "[time_test] Building no-FB (VeeR) for $(TEST)..."; \
	  T0=$$(date +%s%3N); \
	  (cd $$NOFB_DIR && $$BASE_MK FB=0 $(SIM)-build > fb_nofb_build.log 2>&1 && $$BASE_MK FB=0 $(SIM) >> fb_nofb_build.log 2>&1); \
	  T1=$$(date +%s%3N); \
	  NOFB_MS=$$((T1 - T0)); \
	  echo "[time_test] Building FireBridge (FB) for $(TEST)..."; \
	  $(if $(FB_FW_LIB_SRCS),export FB_FW_LIB_SRCS="$(FB_FW_LIB_SRCS)";) \
	  $(if $(FB_FW_LIB_DIRS),export FB_FW_LIB_DIRS="$(FB_FW_LIB_DIRS)";) \
	  $(if $(FB_FW_CFLAGS),export FB_FW_CFLAGS="$(FB_FW_CFLAGS)";) \
	  T2=$$(date +%s%3N); \
	  (cd $$FB_DIR && $$BASE_MK FB=1 \
	    $(if $(FB_FW_LIB_SRCS),FB_FW_LIB_SRCS="$(FB_FW_LIB_SRCS)") \
	    $(if $(FB_FW_LIB_DIRS),FB_FW_LIB_DIRS="$(FB_FW_LIB_DIRS)") \
	    $(if $(FB_FW_CFLAGS),FB_FW_CFLAGS="$(FB_FW_CFLAGS)") \
	    $(SIM)-build > fb_fb_build.log 2>&1 && \
	    $$BASE_MK FB=1 \
	    $(if $(FB_FW_LIB_SRCS),FB_FW_LIB_SRCS="$(FB_FW_LIB_SRCS)") \
	    $(if $(FB_FW_LIB_DIRS),FB_FW_LIB_DIRS="$(FB_FW_LIB_DIRS)") \
	    $(SIM) >> fb_fb_build.log 2>&1); \
	  T3=$$(date +%s%3N); \
	  FB_MS=$$((T3 - T2)); \
	  NOFB_S=$$(echo "scale=2; $$NOFB_MS/1000" | bc); \
	  FB_S=$$(echo "scale=2; $$FB_MS/1000" | bc); \
	  SPD=$$(echo "scale=2; $$NOFB_MS/$$FB_MS" | bc 2>/dev/null || echo "N/A"); \
	  echo ""; \
	  echo "=== time_test results for $(TEST) ==="; \
	  echo "  no-FB: $${NOFB_S}s   FB: $${FB_S}s   speedup: $${SPD}x"; \
	  TS=$$(date +%Y%m%d_%H%M%S); \
	  CSV=$(CONT_CALIPTRA_WS)/../experiments/runs/speedup_$$(echo $(TEST))_$${TS}.csv; \
	  echo "test,nofb_s,fb_s,speedup" > $$CSV; \
	  echo "$(TEST),$$NOFB_S,$$FB_S,$$SPD" >> $$CSV; \
	  echo "  CSV: $$CSV")
