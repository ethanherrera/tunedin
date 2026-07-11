# GitHub Automation Guide

## Responsibility

This directory owns pull-request validation, dependency updates, and later explicitly triggered release workflows.

## Rules

- Keep pull-request checks non-mutating: build, logic test, lint, generated-output verification, and relevant disposable-backend tests only.
- Pull-request and merge-triggered workflows must not deploy to the shared Supabase Development project. The only CI deployment exception is the manually dispatched `Deploy Development Database` workflow, triggered from `main` through `make dev-deploy` and scoped to the protected `Development` environment.
- Do not create TestFlight or production delivery on merge. Those are separate, explicitly triggered workflows after the relevant release gate.
- Use GitHub Environments and secrets for CI-only credentials; never write credentials directly into a workflow.

## Verification

Validate workflow syntax and ensure the affected workflow runs on the pull request before merge.
