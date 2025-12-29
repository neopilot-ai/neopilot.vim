# Copybara import generated
.PHONY: help version tag test clean

# Default target
help:
	@echo "Available targets:"
	@echo "  version    - Show current version"
	@echo "  tag        - Create a new version tag (requires VERSION_TYPE=patch|minor|major)"
	@echo "  test       - Run basic syntax checks"
	@echo "  clean      - Clean up temporary files"
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

# Run basic syntax checks
test:
	@echo "Checking Vim syntax..."
	@find . -name "*.vim" -exec vim -c "set nocompatible" -c "syntax on" -c "source {}" -c "echo 'OK: {}'" \; 2>/dev/null | grep -v "OK:" || echo "Syntax check completed"
	@echo "Checking for VERSION file..."
	@if [ -f VERSION ]; then \
		echo "VERSION file exists: $$(cat VERSION)"; \
	else \
		echo "Warning: VERSION file not found"; \
	fi

# Clean up temporary files
clean:
	@echo "Cleaning up..."
	@find . -name "*.log" -delete 2>/dev/null || true
	@find . -name "*~" -delete 2>/dev/null || true
	@find . -name "*.swp" -delete 2>/dev/null || true
	@echo "Cleanup completed"