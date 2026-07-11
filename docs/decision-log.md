# Implementation Decision Log

## 2026-07-10 — Development email delivery

Supabase’s free default email provider does not permit custom templates. For internal Development-only work, tunedIn temporarily uses the provider’s standard magic-link template while retaining the configured 10-minute token expiry and 60-second resend cooldown.

Before accepting the authentication feature or inviting any external tester, configure Resend (or another approved custom SMTP provider), restore the code-only six-digit OTP template, verify the sender domain, and test the full iOS code-entry flow. Do not ship the magic-link fallback to the private beta.
