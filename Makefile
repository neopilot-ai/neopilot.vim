# Copybara import generated
.PHONY: help version tag test test-unit lint clean install dev-setup docs

# Variables
NVIM := nvim
LUA_CHECKER := luacheck
VIM_CMD := vim

# Default target
help:
	@echo "Available targets:"
	@echo "  version    - Show current version"
	@echo "  tag        - Create a new version tag (requires VERSION_TYPE=patch|minor|major)"
	@echo "  test       - Run all tests (unit and integration)"
	@echo "  test-unit  - Run unit tests using plenary"
	@echo "  lint       - Run linting on Lua and Vim scripts"
	@echo "  clean      - Clean up temporary files"
	@echo "  install    - Install plugin dependencies"
	@echo "  dev-setup  - Set up development environment"
	@echo "  docs       - Generate documentation"
	@echo "  help       - Show this help message"

# Show current version
version:
	@if [ -f VERSION ]; then \
		echo "Current version: $$(cat VERSION)"; \
	else \
		echo "No VERSION file found"; \
	fi

# Create a new version tag locally (for development/testing)
tag:
	@if [ -z "$(VERSION_TYPE)" ]; then \
		echo "Usage: make tag VERSION_TYPE=patch|minor|major"; \
		exit 1; \
	fi; \
	if [ ! -f VERSION ]; then \
		echo "0.0.0" > VERSION; \
	fi; \
	CURRENT=$$(cat VERSION); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	case $(VERSION_TYPE) in \
		major) NEW="$$((MAJOR + 1)).0.0" ;; \
		minor) NEW="$$MAJOR.$$((MINOR + 1)).0" ;; \
		patch) NEW="$$MAJOR.$$MINOR.$$((PATCH + 1))" ;; \
		*) echo "Invalid VERSION_TYPE: $(VERSION_TYPE)"; exit 1 ;; \
	esac; \
	echo $$NEW > VERSION; \
	echo "Updated VERSION to $$NEW"; \
	echo "Tag name would be: v$$NEW"

# Run all tests
test: test-unit
	@echo "All tests completed successfully!"

# Run unit tests using plenary
test-unit:
	@echo "Running unit tests..."
	@if command -v $(NVIM) >/dev/null 2>&1; then \
		$(NVIM) --headless -c "PlenaryBustedDirectory test/plenary" -c "qa"; \
	else \
		echo "Error: nvim not found. Please install Neovim to run tests."; \
		exit 1; \
	fi

# Run linting
lint:
	@echo "Linting Lua files..."
	@if command -v $(LUA_CHECKER) >/dev/null 2>&1; then \
		$(LUA_CHECKER) --std lua51 lua/; \
	else \
		echo "Warning: luacheck not found. Install with: luarocks install luacheck"; \
	fi
	@echo "Checking Vim script syntax..."
	@find . -name "*.vim" -not -path "./.git/*" -exec $(VIM_CMD) -c "set nocompatible" -c "syntax on" -c "source {}" -c "qa" \; 2>/dev/null || echo "Vim syntax check completed"

# Install plugin dependencies
install:
	@echo "Installing dependencies..."
	@if command -v $(NVIM) >/dev/null 2>&1; then \
		echo "Checking for plenary.nvim..."; \
		$(NVIM) --headless -c "try require('plenary')" -c "echo 'plenary.nvim found'" -c "qa" 2>/dev/null || echo "Warning: plenary.nvim not found. Please install it."; \
	else \
		echo "Error: nvim not found. Please install Neovim."; \
		exit 1; \
	fi

# Set up development environment
dev-setup: install
	@echo "Setting up development environment..."
	@if command -v luarocks >/dev/null 2>&1; then \
		echo "Installing luacheck for Lua linting..."; \
		luarocks install luacheck; \
	else \
		echo "Warning: luarocks not found. Skipping luacheck installation."; \
	fi
	@echo "Development setup completed!"

# Generate documentation
docs:
	@echo "Generating documentation..."
	@if [ -f "doc/neopilot.txt" ]; then \
		echo "Documentation exists at doc/neopilot.txt"; \
		$(VIM_CMD) -c "helptags doc/" -c "qa"; \
		echo "Help tags generated"; \
	else \
		echo "No documentation file found at doc/neopilot.txt"; \
	fi

# Clean up temporary files
clean:
	@echo "Cleaning up..."
	@find . -name "*.log" -delete 2>/dev/null || true
	@find . -name "*~" -delete 2>/dev/null || true
	@find . -name "*.swp" -delete 2>/dev/null || true
	@find . -name "*.swo" -delete 2>/dev/null || true
	@find . -name ".#*" -delete 2>/dev/null || true
	@find . -name "#*#" -delete 2>/dev/null || true
	@echo "Cleanup completed"