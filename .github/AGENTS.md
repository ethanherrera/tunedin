# GitHub Automation Guide

## Responsibility

This directory owns pull-request validation, dependency updates, and later explicitly triggered release workflows.

## Rules

- Keep pull-request checks non-mutating: build, logic test, lint, generated-output verification, and relevant disposable-backend tests only.
- Pull-request and merge-triggered workflows must not deploy to the shared Supabase Development project. The only CI deployment exceptions are the manually dispatched Development database and Function workflows, triggered from an explicitly requested branch through `make dev-deploy` or `make dev-functions-deploy` and scoped to the protected `Development` environment.
- Do not create TestFlight or production delivery on merge. Those are separate, explicitly triggered workflows after the relevant release gate.
- Staging promotion is manually dispatched from `main`, targets the protected `Staging` environment, and promotes backend migrations/functions before uploading the already archived `tunedIn Staging` build. Never trigger it automatically on merge.
- A future Production promotion must verify that the exact source commit has a successful Staging deployment before it can access Production credentials or mutate Production.
- Use GitHub Environments and secrets for CI-only credentials; never write credentials directly into a workflow.

## Verification

Validate workflow syntax and ensure the affected workflow runs on the pull request before merge.
