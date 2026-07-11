# PostHog

## Purpose

Operate tunedIn’s privacy-restricted PostHog observability projects. The iOS SDK remains deferred until beta readiness; this runbook governs project configuration and access only.

## Projects

- `tunedIn Development` — project ID `507315`
- `tunedIn Staging` — project ID `507318`
- `tunedIn Production` — project ID `507319`
- Region: US
- Management API key location: macOS Keychain item `tunedin/posthog/management-api`

## Applied privacy settings

- IP anonymization enabled.
- Autocapture, exception autocapture, web-vitals autocapture, console capture, automatic performance capture, session replay, heatmaps, and persisted feature flags disabled.
- No experiments or feature flags are to be created for the MVP.
- The iOS client will later send only the approved explicit telemetry events through an app-owned wrapper.

## Retention

All three projects currently report an 84-month event-retention setting. The Management API does not apply the requested one-month value, so use the PostHog dashboard’s retention/billing controls to set the shortest available retention at or below 30 days before beta readiness. Do not mix Development data with beta or production data.

## Verification

Use the Management API with the Keychain key to inspect project settings. Confirm the disabled settings listed above before SDK integration or every release-related configuration change.

## Recovery and audit

- If a management key is exposed, revoke it in PostHog and replace the Keychain item immediately.
- Record the affected project and configuration change in the pull request.
- Review privacy settings monthly during beta and after every PostHog plan change.
