SHELL := /bin/bash

PROJECT := tunedIn.xcodeproj
SCHEME := tunedIn-Development
LOCAL_SCHEME := tunedIn-Local
DESTINATION := platform=iOS Simulator,name=iPhone 13

.DEFAULT_GOAL := help

.PHONY: help setup configure local-db-start configure-local-supabase local-next-steps generate format lint workflow-lint distribution-metadata-verify posthog-test posthog-plan posthog-verify posthog-apply build build-local build-staging archive-staging test test-local check simulator-auth-link simulator-local simulator-live simulator-signed-out simulator-onboarding simulator-profile simulator-profile-error local-db-reset local-seed-verify supabase-types check-supabase-types backend-test storage-integration-test backend-verify dev-status dev-plan dev-deploy dev-login-link staging-status staging-plan staging-promote

help: ## List available development commands.
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z_-]+:.*##/ { printf "%-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

setup: ## Verify the local native and backend toolchain.
	@./scripts/verify-tools.sh

configure: ## Create ignored local Xcode configuration files from templates.
	@./scripts/configure-local.sh

local-db-start: ## Start or reuse the disposable local Supabase stack without changing its data.
	@supabase start >/dev/null

configure-local-supabase: local-db-start ## Point the ignored Local Xcode configuration at the local Supabase stack.
	@./scripts/configure-local-supabase.sh

generate: ## Regenerate the committed Xcode project from project.yml.
	@xcodegen generate --spec project.yml

format: ## Format Swift source on the current branch.
	@swiftformat ios/tunedIn/Sources ios/tunedIn/Tests --config .swiftformat \
		--exclude ios/tunedIn/Sources/Data/Generated

lint: ## Check Swift style without changing files.
	@swiftlint lint --config .swiftlint.yml

workflow-lint: ## Validate GitHub Actions workflow syntax and expressions.
	@actionlint

distribution-metadata-verify: ## Validate App Store bundle metadata and the opaque 1024-pixel app icon.
	@./scripts/verify-distribution-metadata.sh

posthog-test: ## Validate the offline telemetry contract and PostHog control-plane tests.
	@python3 scripts/posthog_control.py validate
	@python3 -m unittest discover -s scripts/tests -p 'test_posthog_control.py'

posthog-plan: ## Show read-only drift for the approved PostHog Staging project.
	@python3 scripts/posthog_control.py plan

posthog-verify: ## Fail when PostHog Staging differs from the tracked contract.
	@python3 scripts/posthog_control.py verify

posthog-apply: ## Apply the tracked contract to PostHog Staging (confirmation required).
	@python3 scripts/posthog_control.py apply

build: generate ## Build the Development scheme for the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

build-local: generate ## Build the Local Supabase scheme for the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(LOCAL_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

build-staging: generate ## Build the Staging scheme for the iPhone 13 Simulator without signing.
	@xcodebuild -project $(PROJECT) -scheme tunedIn-Staging -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO build

archive-staging: generate ## Create a signed local Staging archive for manual Xcode validation.
	@mkdir -p build
	@xcodebuild -project $(PROJECT) -scheme tunedIn-Staging -configuration Staging \
		-destination 'generic/platform=iOS' -archivePath build/tunedIn-Staging.xcarchive archive

test: generate ## Run the Swift Testing suite on the iPhone 13 Simulator.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test

test-local: generate ## Run the Swift Testing suite with Local Supabase configuration.
	@xcodebuild -project $(PROJECT) -scheme $(LOCAL_SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO test

check: generate lint workflow-lint distribution-metadata-verify posthog-test test ## Run generation, linting, workflow, telemetry, metadata, and logic tests.

simulator-auth-link: ## Open a copied Supabase sign-in link in the booted Simulator.
	@./scripts/open-simulator-auth-link.sh

simulator-local: ## Start Local Supabase, configure, build, install, and launch without resetting local data.
	@$(MAKE) configure-local-supabase
	@$(MAKE) build-local
	@./scripts/install-local-simulator.sh
	@$(MAKE) --no-print-directory local-next-steps

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
	@./scripts/reset-local-supabase.sh
	@./scripts/verify-local-seed.sh
	@$(MAKE) --no-print-directory local-next-steps

local-seed-verify: ## Verify the deterministic local Supabase journey catalog.
	@./scripts/verify-local-seed.sh

local-next-steps:
	@printf '\nNext steps for Local testing:\n'
	@printf '  1. In the app, tap Continue as Local Listener (no email link needed).\n'
	@printf '  2. Use Choose another seeded account to switch journeys.\n'
	@printf '  Other journeys: newcomer for onboarding; sasha/theo/june for request states.\n'
	@printf '  To test email auth itself, use Inbucket at http://127.0.0.1:54324 and make simulator-auth-link.\n\n'

supabase-types: ## Generate Swift database DTOs from the migrated local schema.
	@./scripts/generate-supabase-types.sh

check-supabase-types: ## Fail when generated Swift DTOs differ from the local schema.
	@./scripts/check-supabase-types.sh

backend-test: ## Run pgTAP tests against a disposable local Supabase stack.
	@supabase test db

storage-integration-test: ## Exercise private avatar authorization through the Local Storage API.
	@./scripts/test-profile-storage-api.sh

backend-verify: local-db-reset check-supabase-types backend-test storage-integration-test ## Rebuild and verify schema, types, RLS, and Storage API behavior.

dev-status: ## Show remote migration parity for the hosted tunedin-dev database.
	@./scripts/development-database.sh status

dev-plan: ## Print migrations that would be applied to hosted tunedin-dev.
	@./scripts/development-database.sh plan

dev-deploy: ## Trigger the manually approved Development migration workflow from main.
	@gh workflow run deploy-development.yml --ref main -f confirm=deploy-development
	@printf 'Queued the Development migration workflow. Review its GitHub Actions summary for the deployed commit and migration parity.\n'

dev-login-link: ## Copy a no-email tunedin-dev login link (EMAIL=user@example.com).
	@./scripts/generate-development-login-link.sh

staging-status: ## Show remote migration parity for tunedin-staging (SUPABASE_PROJECT_REF required).
	@./scripts/staging-environment.sh status

staging-plan: ## Print migrations that would be applied to tunedin-staging.
	@./scripts/staging-environment.sh plan

staging-promote: ## Trigger the protected Staging backend and TestFlight promotion from main.
	@gh workflow run promote-staging.yml --ref main -f confirm=promote-staging
	@printf 'Queued the Staging promotion. Follow its GitHub Actions deployment summary in the UI.\n'
