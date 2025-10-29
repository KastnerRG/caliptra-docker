test ?= hello_world_iccm
sim ?= vcs
TESTDIR := $(CALIPTRA_WORKSPACE)/work/$(test)_$(sim)
SUITES_DIR1 := $(CALIPTRA_ROOT)/src/integration/test_suites
SUITES_DIR2 := $(CALIPTRA_ROOT)/src/integration/uvmf_caliptra_top/uvmf_template_output/project_benches/caliptra_top/tb/tests/src

run:
	rm -rf $(TESTDIR)
	mkdir -p $(TESTDIR)
	$(MAKE) -C $(TESTDIR) -f $(CALIPTRA_ROOT)/tools/scripts/Makefile test=$(test) debug=1 $(sim) | tee work/$(test)_$(sim).log

list:
	@for d in $(SUITES_DIR1) $(SUITES_DIR2); do \
		[ -d "$$d" ] && find "$$d" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; ; \
	done

clean:
	rm -rf ./work
	$(MAKE) -f $(CALIPTRA_ROOT)/tools/scripts/Makefile clean