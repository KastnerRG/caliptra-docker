test ?= hello_world_iccm
sim ?= vcs
TESTDIR := $(CALIPTRA_WORKSPACE)/work/$(test)_$(sim)

run:
	rm -rf $(TESTDIR)
	mkdir -p '$(TESTDIR)'
	$(MAKE) -C '$(TESTDIR)' -f '$(CALIPTRA_ROOT)/tools/scripts/Makefile' test='$(test)' debug=1 $(sim) | tee 'work/$(test)_$(sim).log'

clean:
	rm -rf ./work