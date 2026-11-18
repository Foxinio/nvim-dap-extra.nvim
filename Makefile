NVIM ?= nvim
DEPS := mfussenegger/nvim-dap theHamsta/nvim-dap-virtual-text
# test-live also needs the dap-ui fork: make deps-live
LIVE_DEPS := Foxinio/nvim-dap-ui nvim-neotest/nvim-nio
# Directory holding the dependencies; defaults to lazy.nvim's plugin directory.
export DEPS_DIR

.PHONY: test test-live deps deps-live

test:
	@for t in test test_controls; do $(NVIM) --headless -u NONE -l tests/$$t.lua || exit 1; done

# Needs gcc, gdb, ptrace, cpptools' OpenDebugAD7 (Mason) and the dap-ui fork.
test-live:
	@for t in test_focus_live test_exceptions_live; do $(NVIM) --headless -u NONE -l tests/$$t.lua || exit 1; done

deps:
	@mkdir -p .deps
	@for r in $(DEPS); do d=".deps/$${r#*/}"; [ -d "$$d" ] || git clone -q --depth 1 "https://github.com/$$r" "$$d"; done

deps-live: deps
	@for r in $(LIVE_DEPS); do d=".deps/$${r#*/}"; [ -d "$$d" ] || git clone -q --depth 1 "https://github.com/$$r" "$$d"; done
