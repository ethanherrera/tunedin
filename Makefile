SHELL := /bin/bash

PROJECT := tunedIn.xcodeproj
SCHEME := tunedIn-Development
DESTINATION := platform=iOS Simulator,name=iPhone 13

.DEFAULT_GOAL := help

.PHONY: help setup configure generate format lint build test check supabase-types check-supabase-types backend-test

help: ## List available development commands.
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z_-]+:.*##/ { printf "%-18s %s\\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## Verify the local native and backend toolchain.
	@./scripts/verify-tools.sh

configure: ## Create ignored local Xcode configuration files from templates.
	@./scripts/configure-local.sh

generate: ## Regenerate the committed Xcode project from project.yml.
	@xcodegen generate --spec project.yml

format: ## Format Swift source on the current branch.
	@swiftformat ios/tunedIn/Sources ios/tunedIn/Tests --config .swiftformat

lint: ## Check Swift style without changing files.
	@swiftlint lint --config .swiftlint.yml

build: generate ## Build the Development scheme for the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

test: generate ## Run the Swift Testing suite on the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test

check: generate lint test ## Run generation, linting, and logic tests.

supabase-types: ## Generate and commit Swift database DTOs for the linked project.
	@./scripts/generate-supabase-types.sh

check-supabase-types: ## Fail when generated Swift DTOs differ from the local schema.
	@./scripts/check-supabase-types.sh

backend-test: ## Run pgTAP tests against a disposable local Supabase stack.
	@supabase test db
