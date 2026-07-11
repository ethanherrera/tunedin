# PostHog

## Purpose

Operate tunedIn’s privacy-restricted PostHog observability projects. The iOS SDK remains deferred until beta readiness; this runbook governs project configuration and access only.

## Current Development project

- Project: `tunedIn Development`
- Project ID: `507315`
- Region: US
- Management API key location: macOS Keychain item `tunedin/posthog/management-api`

## Applied privacy settings

- IP anonymization enabled.
- Autocapture, exception autocapture, web-vitals autocapture, console capture, automatic performance capture, session replay, heatmaps, and persisted feature flags disabled.
- No experiments or feature flags are to be created for the MVP.
- The iOS client will later send only the approved explicit telemetry events through an app-owned wrapper.

## Current plan constraints

The active free plan allows one PostHog project and retains events for 84 months. It cannot meet the MVP requirement for separate Development, Staging, and Production projects or 30-day retention.

Before beta readiness, upgrade through the PostHog billing UI, create `tunedIn Staging` and `tunedIn Production`, set each project to the shortest available retention at or below 30 days, and duplicate the privacy settings above. Do not mix Development data with beta or production data.

## Verification

Use the Management API with the Keychain key to inspect project settings. Confirm the disabled settings listed above before SDK integration or every release-related configuration change.

## Recovery and audit

- If a management key is exposed, revoke it in PostHog and replace the Keychain item immediately.
- Record the affected project and configuration change in the pull request.
- Review privacy settings monthly during beta and after every PostHog plan change.
