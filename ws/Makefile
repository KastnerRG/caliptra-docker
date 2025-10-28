test ?= hello_world_iccm
sim ?= vcs
TESTDIR := $(CALIPTRA_WORKSPACE)/work-$(sim)/usr/$(test)

run:
	@mkdir -p '$(TESTDIR)'
	@rm -rf '$(TESTDIR)'/*
	@$(MAKE) -C '$(TESTDIR)' -f '$(CALIPTRA_ROOT)/tools/scripts/Makefile' test='$(test)' debug=1 $(sim) | tee './$(test)_$(sim).log'

help:
	@printf "Usage: make [test=hello_world_iccm|smoke_test_sha256|smoke_test_veer] [sim=vcs|verilator]\n"