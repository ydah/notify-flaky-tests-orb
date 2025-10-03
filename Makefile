# Makefile for Flaky Tests Notify Orb development

.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

.PHONY: validate
validate: ## Validate the orb configuration
	@echo "Packing orb..."
	@circleci orb pack src > orb.yml
	@echo "Validating orb..."
	@circleci orb validate orb.yml
	@echo "✓ Orb validation successful"

.PHONY: shellcheck
shellcheck: ## Run shellcheck on all shell scripts
	@echo "Running shellcheck..."
	@shellcheck src/scripts/*.sh
	@echo "✓ ShellCheck passed"

.PHONY: yamllint
yamllint: ## Run yamllint on all YAML files
	@echo "Running yamllint..."
	@yamllint -c .yamllint src/
	@echo "✓ YAML lint passed"

.PHONY: lint
lint: shellcheck yamllint ## Run all linters

.PHONY: test
test: validate lint ## Run all tests and validations

.PHONY: pack
pack: ## Pack the orb from source
	@circleci orb pack src > orb.yml
	@echo "✓ Orb packed to orb.yml"

.PHONY: publish-dev
publish-dev: test ## Publish a development version of the orb
	@echo "Publishing development version..."
	@circleci orb publish orb.yml ydah/notify-flaky-tests@dev:latest
	@echo "✓ Development version published"

.PHONY: publish
publish: ## Publish a production version (requires version parameter)
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make publish VERSION=2.0.0"; \
		exit 1; \
	fi
	@echo "Publishing version $(VERSION)..."
	@circleci orb publish orb.yml ydah/notify-flaky-tests@$(VERSION)
	@echo "✓ Version $(VERSION) published"

.PHONY: docker-test
docker-test: ## Run tests using Docker Compose
	@echo "Running tests in Docker..."
	@docker-compose run --rm test-environment
	@echo "✓ Docker tests completed"

.PHONY: docker-lint
docker-lint: ## Run linters using Docker Compose
	@echo "Running linters in Docker..."
	@docker-compose run --rm shellcheck
	@docker-compose run --rm yamllint
	@echo "✓ Docker lint completed"

.PHONY: clean
clean: ## Clean generated files
	@rm -f orb.yml
	@rm -f /tmp/flaky_tests_metrics*
	@echo "✓ Cleaned generated files"

.PHONY: install-cli
install-cli: ## Install CircleCI CLI
	@echo "Installing CircleCI CLI..."
	@curl -fLSs https://circle.ci/cli | bash
	@echo "✓ CircleCI CLI installed"

.PHONY: setup
setup: install-cli ## Setup development environment
	@echo "Setting up development environment..."
	@echo "✓ Development environment ready"

.PHONY: examples
examples: ## Show example configurations
	@echo "Basic example:"
	@echo "-------------"
	@cat src/examples/basic.yml
	@echo ""
	@echo "Scheduled example:"
	@echo "-----------------"
	@cat src/examples/scheduled.yml

.PHONY: version
version: ## Show current orb version
	@grep "version:" src/@orb.yml | head -1

.PHONY: changelog
changelog: ## Show recent changelog entries
	@echo "Recent changes:"
	@echo "---------------"
	@head -30 CHANGELOG.md
