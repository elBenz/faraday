# ADR 0001: launchd weak-moment resistance posture

- Status: Accepted
- Date: 2026-05-21
- Related issue: faraday-16z
- Related PRD: `docs/PRD.md` (User stories 26–28, 39–40; implementation decisions on launchd)

## Context

Faraday needs launch-at-login/startup behavior and crash restart to keep enforcement available during strict sessions. We also need an honest weak-moment resistance posture: harder to casually disable, but not pretending to defeat a local admin.

Options considered:

1. User `LaunchAgent` only
2. Root-owned `LaunchDaemon` only
3. Staged support for both

## Decision

Choose **staged support for both**:

- **MVP default:** user `LaunchAgent` for easy install/uninstall and low operational risk.
- **Serious mode:** optional root-owned `LaunchDaemon` for higher friction against casual unload/kill.

Both modes use `KeepAlive` restart behavior.

## Rationale

- `LaunchAgent` aligns with MVP speed, local-first setup, and easier contributor testing.
- Optional `LaunchDaemon` better matches weak-moment resistance goals for committed users.
- Staged support avoids blocking MVP on privileged installer complexity.
- This posture is explicit about limits: local-admin users can still disable protections.

## Consequences

- We must document install/restart/remove flows for both modes.
- Manual smoke tests are required for startup and crash-restart behavior.
- Future implementation should keep one core daemon executable and separate launchd plist configs per mode.

## Weak-moment resistance limits (explicit)

Faraday is **B-level anti-bypass**, not adversarial endpoint security:

- A local admin can still unload launchd jobs, replace binaries, or disable enforcement.
- Root-owned daemon mode increases friction for impulsive bypass, but does not make bypass impossible.
- Product claims should stay behavioral: reduce weak-moment failure, not guarantee tamper-proof control.
