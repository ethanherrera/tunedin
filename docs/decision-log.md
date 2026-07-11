# Implementation Decision Log

## 2026-07-10 — Development email delivery

Supabase’s free default email provider does not permit custom templates. For internal Development-only work, tunedIn temporarily uses the provider’s standard magic-link template while retaining the configured 10-minute token expiry and 60-second resend cooldown.

Before accepting the authentication feature or inviting any external tester, configure Resend (or another approved custom SMTP provider), restore the code-only six-digit OTP template, verify the sender domain, and test the full iOS code-entry flow. Do not ship the magic-link fallback to the private beta.

## 2026-07-10 — PostHog retention

PostHog Development, Staging, and Production projects are separated and have the approved privacy controls disabled. All three currently retain events for 84 months; the Management API did not apply the requested 30-day value, so retention was intentionally left unchanged rather than guessed through billing settings.

Before beta readiness, review PostHog’s retention controls and set the shortest available period at or below 30 days if the selected plan supports it. Do not copy raw telemetry to another system to work around this limit.
