# GitHub Automation Guide

## Responsibility

This directory owns pull-request validation, dependency updates, and later explicitly triggered release workflows.

## Rules

- Keep pull-request checks non-mutating: build, logic test, lint, generated-output verification, and relevant disposable-backend tests only.
- Do not deploy to the shared Supabase Development project from CI. Development deployments are explicit terminal actions from a reviewed feature branch.
- Do not create TestFlight or production delivery on merge. Those are separate, explicitly triggered workflows after the relevant release gate.
- Use GitHub Environments and secrets for CI-only credentials; never write credentials directly into a workflow.

## Verification

Validate workflow syntax and ensure the affected workflow runs on the pull request before merge.
