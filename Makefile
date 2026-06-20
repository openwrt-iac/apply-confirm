.PHONY: test test-unit test-integration lint lint-emdash lint-shell stage vm-setup vm-start vm-wait vm-stop clean help

PKG := apply-confirm
STAGE := build/openwrt/$(PKG)/files

help:
	@echo "Targets:"
	@echo "  test               run unit tests and lint"
	@echo "  test-unit          run shell unit tests only"
	@echo "  test-integration   boot VM, run integration tests, stop VM"
	@echo "  lint               em-dash check + shellcheck"
	@echo "  lint-emdash        forbid em-dashes in tracked sources"
	@echo "  lint-shell         shellcheck all shell sources"
	@echo "  stage              populate $(STAGE)/ for SDK package build"
	@echo "  vm-setup/start/wait/stop   manage the OpenWrt QEMU VM"

test: lint test-unit

test-unit:
	@tests/run_unit.sh

lint: lint-emdash lint-shell

lint-emdash:
	@if grep -rn $$'\xe2\x80\x94' src files tests docs design Makefile README.md CLAUDE.md 2>/dev/null; then \
		echo ""; echo "em-dash found in source files (forbidden per CLAUDE.md style)"; exit 1; \
	fi

# busybox ash is the target shell, so check with -s sh. shellcheck is advisory
# locally (may be absent); CI installs it.
lint-shell:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed, skipping"; exit 0; }
	@shellcheck -s sh src/apply-confirm src/lib/*.sh \
		files/etc/init.d/apply-confirm \
		files/etc/hotplug.d/ntp/20-apply-confirm \
		files/etc/uci-defaults/99-apply-confirm \
		tests/run_unit.sh tests/unit/*.sh \
		tests/vm/*.sh tests/integration/run.sh \
		tests/integration/lib/*.sh tests/integration/*_test.sh

stage:
	@rm -rf $(STAGE)
	@mkdir -p $(STAGE)/usr/sbin
	@mkdir -p $(STAGE)/usr/lib/$(PKG)
	@mkdir -p $(STAGE)/etc/config
	@mkdir -p $(STAGE)/etc/init.d
	@mkdir -p $(STAGE)/etc/hotplug.d/ntp
	@mkdir -p $(STAGE)/etc/uci-defaults
	@cp src/apply-confirm                       $(STAGE)/usr/sbin/apply-confirm
	@cp src/lib/*.sh                            $(STAGE)/usr/lib/$(PKG)/
	@cp files/etc/config/apply-confirm          $(STAGE)/etc/config/apply-confirm
	@cp files/etc/init.d/apply-confirm          $(STAGE)/etc/init.d/apply-confirm
	@cp files/etc/hotplug.d/ntp/20-apply-confirm $(STAGE)/etc/hotplug.d/ntp/20-apply-confirm
	@cp files/etc/uci-defaults/99-apply-confirm $(STAGE)/etc/uci-defaults/99-apply-confirm
	@cp VERSION                                 $(STAGE)/VERSION
	@chmod +x $(STAGE)/usr/sbin/apply-confirm \
	          $(STAGE)/etc/init.d/apply-confirm \
	          $(STAGE)/etc/uci-defaults/99-apply-confirm
	@echo "staged to $(STAGE)/"

vm-setup:
	@tests/vm/setup.sh

vm-start:
	@tests/vm/start.sh

vm-wait:
	@tests/vm/wait.sh

vm-stop:
	@tests/vm/stop.sh

test-integration: vm-setup vm-start
	@trap 'tests/vm/stop.sh' EXIT INT TERM; \
	 tests/vm/wait.sh && tests/integration/run.sh

clean:
	@rm -rf build/sdk $(STAGE)
