NVIM ?= nvim
DEPS := mfussenegger/nvim-dap Foxinio/nvim-dap-ui nvim-neotest/nvim-nio theHamsta/nvim-dap-virtual-text
# Directory holding the dependencies; defaults to lazy.nvim's plugin directory.
export DEPS_DIR

.PHONY: test test-live deps

test:
	@for t in test test_controls test_panes; do $(NVIM) --headless -u NONE -l tests/$$t.lua || exit 1; done

# Needs gcc, gdb, ptrace and cpptools' OpenDebugAD7 (Mason).
test-live:
	@for t in test_focus_live test_exceptions_live; do $(NVIM) --headless -u NONE -l tests/$$t.lua || exit 1; done

deps:
	@mkdir -p .deps
	@for r in $(DEPS); do d=".deps/$${r#*/}"; [ -d "$$d" ] || git clone -q --depth 1 "https://github.com/$$r" "$$d"; done
