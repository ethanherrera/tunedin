SHELL := /bin/bash

PROJECT := tunedIn.xcodeproj
SCHEME := tunedIn-Development
LOCAL_SCHEME := tunedIn-Local
DESTINATION := platform=iOS Simulator,name=iPhone 13

.DEFAULT_GOAL := help

.PHONY: help setup configure configure-local-supabase generate format lint build build-local test test-local check simulator-auth-link simulator-local simulator-live simulator-signed-out simulator-onboarding simulator-profile simulator-profile-error local-db-reset supabase-types check-supabase-types backend-test

help: ## List available development commands.
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z_-]+:.*##/ { printf "%-18s %s\\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## Verify the local native and backend toolchain.
	@./scripts/verify-tools.sh

configure: ## Create ignored local Xcode configuration files from templates.
	@./scripts/configure-local.sh

configure-local-supabase: ## Point the ignored Local Xcode configuration at the running local Supabase stack.
	@./scripts/configure-local-supabase.sh

generate: ## Regenerate the committed Xcode project from project.yml.
	@xcodegen generate --spec project.yml

format: ## Format Swift source on the current branch.
	@swiftformat ios/tunedIn/Sources ios/tunedIn/Tests --config .swiftformat \
		--exclude ios/tunedIn/Sources/Data/Generated

lint: ## Check Swift style without changing files.
	@swiftlint lint --config .swiftlint.yml

build: generate ## Build the Development scheme for the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

build-local: generate ## Build the Local Supabase scheme for the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(LOCAL_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

test: generate ## Run the Swift Testing suite on the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test

test-local: generate ## Run the Swift Testing suite with Local Supabase configuration.
	@xcodebuild -project $(PROJECT) -scheme $(LOCAL_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test

check: generate lint test ## Run generation, linting, and logic tests.

simulator-auth-link: ## Open a copied Supabase sign-in link in the booted Simulator.
	@./scripts/open-simulator-auth-link.sh

simulator-local: build-local ## Install and launch the Local Supabase build in the booted Simulator.
	@./scripts/install-local-simulator.sh

simulator-live: build ## Install and launch the fresh Development app with live Supabase repositories.
	@./scripts/launch-development-scenario.sh live

simulator-signed-out: build ## Install and launch the fresh Development app at the deterministic sign-in screen.
	@./scripts/launch-development-scenario.sh signed-out

simulator-onboarding: build ## Install and launch the fresh Development app with deterministic onboarding fixtures.
	@./scripts/launch-development-scenario.sh onboarding

simulator-profile: build ## Install and launch the fresh Development app with a deterministic completed profile.
	@./scripts/launch-development-scenario.sh profile

simulator-profile-error: build ## Install and launch the fresh Development app with a deterministic profile failure.
	@./scripts/launch-development-scenario.sh profile-error

local-db-reset: ## Reset the disposable local Supabase database, migrations, and development seed.
	@supabase start
	@supabase db reset

supabase-types: ## Generate Swift database DTOs from the migrated local schema.
	@./scripts/generate-supabase-types.sh

check-supabase-types: ## Fail when generated Swift DTOs differ from the local schema.
	@./scripts/check-supabase-types.sh

backend-test: ## Run pgTAP tests against a disposable local Supabase stack.
	@supabase test db
