# PRD: Faraday Working MVP

## Problem Statement

The user wants to do strict focus work on a Mac without repeatedly picking up their iPhone. Existing focus tools are easy to bypass because they depend on intention, app limits, or phone-side friction. Faraday should create physical discipline: during a strict session, the phone-attached beacon must be in an acceptable phone location, not in the forbidden phone area near the desk.

The previous v0 work produced useful core concepts and documentation, but not a working end-to-end product. The next phase must turn Faraday into a working or almost-working MVP: a real daemon, real beacon sensing when hardware is available, real calibrated proximity classification, a prominent native overlay, native macOS lock enforcement in armed mode, and a polished Bun terminal UI for setup and control.

The user does not yet have the beacon hardware. Until the parcel arrives, Faraday needs a simulated observation source that drives the same daemon, TUI, persistence, overlay, and enforcement paths as the real BLE source. Simulation is useful for development, but it is not valid final Working MVP evidence.

## Solution

Build Faraday as a local-first macOS enforcement system made of three cooperating processes:

- A Swift daemon that owns sensing, classification, session state, persistence, overlay launching, session notifications, and native lock enforcement.
- A Swift native overlay helper that appears prominently across displays during violations or beacon-trust failures.
- A Bun terminal UI that provides setup, simulation, calibration, session control, status, and event inspection through the daemon's local Unix domain socket JSON-RPC API.

Faraday will use user-calibrated meaning rather than generic distance language. The user calibrates a forbidden phone area, usually the desk or within easy reach, and one or more acceptable phone locations where the phone may live during focus. One acceptable location is enough to start; three distinct acceptable locations are recommended for better confidence. The classifier reports `forbidden`, `acceptable`, `uncertain`, or `missing`.

Dry-run enforcement is the default. It records lock requests and shows warnings without locking macOS. Armed enforcement must be explicitly enabled and is only allowed after beacon identity, calibration, and confidence requirements are satisfied. In armed mode, sustained forbidden proximity during an active strict session triggers a native Faraday-themed overlay countdown and then locks macOS using a native lock adapter.

If the configured beacon becomes missing long enough that Faraday cannot trust proximity, Faraday does not lock from missing alone. It marks the session degraded/invalid, warns clearly, and requires revalidation: the beacon must be seen again in the forbidden phone area, then moved back to an acceptable phone location before strict enforcement resumes.

## User Stories

1. As a distracted Mac user, I want Faraday to keep my phone out of the forbidden phone area, so that I cannot casually check it during focus work.
2. As a distracted Mac user, I want Faraday to use a phone-attached beacon, so that macOS can infer phone proximity without an iOS app.
3. As a distracted Mac user, I want to define my forbidden phone area, so that Faraday enforces my actual weak spot rather than a generic distance.
4. As a distracted Mac user, I want to define acceptable phone locations, so that the phone can live wherever works for my room.
5. As a distracted Mac user, I want acceptable locations to include another room, a hallway, a drawer, a shelf, or a farther-away same-room spot, so that Faraday fits my real environment.
6. As a distracted Mac user, I want calibration to warn me when acceptable locations are too similar to the forbidden phone area, so that I do not trust unreliable enforcement.
7. As a distracted Mac user, I want one acceptable location to be enough for basic calibration, so that setup is not too heavy.
8. As a distracted Mac user, I want Faraday to recommend three acceptable locations, so that classification has better confidence.
9. As a distracted Mac user, I want Faraday to block armed enforcement when calibration confidence is weak, so that it does not lock my Mac from bad thresholds.
10. As a distracted Mac user, I want dry-run mode by default, so that I can test behavior without risking unexpected locks.
11. As a distracted Mac user, I want armed mode to be explicit and obvious, so that I always know when Faraday can lock my Mac.
12. As a distracted Mac user, I want Faraday to require configured beacon identity before arming, so that unrelated BLE devices do not control enforcement.
13. As a distracted Mac user, I want Faraday to require calibration before arming, so that native lock behavior is based on my own setup.
14. As a distracted Mac user, I want to start a strict session from the TUI, so that I can begin enforcement quickly from the terminal.
15. As a distracted Mac user, I want Faraday to confirm the beacon starts in the forbidden phone area, so that it knows the beacon is alive and attached before the session begins.
16. As a distracted Mac user, I want Faraday to wait until the beacon reaches acceptable proximity before the strict session becomes active, so that I physically move the phone away before work starts.
17. As a distracted Mac user, I want Faraday to show current classification, so that I understand whether the phone is forbidden, acceptable, uncertain, or missing.
18. As a distracted Mac user, I want uncertain proximity to warn but not lock, so that ambiguous BLE readings do not cause false locks.
19. As a distracted Mac user, I want uncertain proximity to not count as acceptable recovery, so that Faraday does not resume strict claims too early.
20. As a distracted Mac user, I want a prominent native overlay when the phone is in the forbidden phone area, so that I notice even when I am not watching the terminal.
21. As a distracted Mac user, I want the overlay to use a Faraday electrical/electromagnetic theme, so that the product feels cohesive and motivating.
22. As a distracted Mac user, I want violation copy to be clear but lightly themed, so that it feels serious without being annoying or embarrassing.
23. As a distracted Mac user, I want the first violation countdown to last about 30 seconds, so that accidental proximity can be corrected.
24. As a distracted Mac user, I want Faraday to lock macOS if the phone remains in the forbidden phone area after the countdown, so that the weak-moment loop is interrupted.
25. As a distracted Mac user, I want a shorter 10–15 second countdown after unlock if the phone is still forbidden, so that relocking is clean but not silent.
26. As a distracted Mac user, I want Faraday to detect unlock/session-active events cleanly, so that post-unlock checks are reliable.
27. As a distracted Mac user, I want Faraday to never lock from a missing beacon alone, so that BLE dropouts do not punish me with false locks.
28. As a distracted Mac user, I want missing beacon during an active session to mark the session degraded/invalid, so that Faraday is honest when it cannot trust the sensor.
29. As a distracted Mac user, I want missing-beacon recovery to require revalidating the beacon in the forbidden phone area and then moving it back to acceptable proximity, so that Faraday regains chain of trust.
30. As a distracted Mac user, I want local event logs, so that I can inspect session starts, classification changes, warnings, lock requests, dry-run skips, native lock attempts, missing-beacon degradation, and calibration results.
31. As a distracted Mac user, I want a TUI dashboard, so that I can see daemon status, current source, enforcement mode, classification, session state, overlay state, and recent events.
32. As a distracted Mac user, I want simulation controls in the TUI before my beacon arrives, so that I can validate the end-to-end flow early.
33. As a distracted Mac user, I want simulation to use the same daemon path as real BLE, so that simulated success exercises real architecture.
34. As a distracted Mac user, I want Faraday to support real iBeacon scan-and-select setup, so that I do not mistype UUID, major, or minor values.
35. As a distracted Mac user, I want manual beacon identity entry as a fallback, so that setup still works if I already know the beacon identifiers.
36. As a distracted Mac user, I want a live RSSI display during setup and calibration, so that I can see signal behavior while placing the beacon.
37. As a distracted Mac user, I want calibration sampling to show progress, median, variance/noise, and a sparkline, so that I trust the measurements.
38. As a distracted Mac user, I want to redo a calibration sample, so that accidental movement or noise does not poison thresholds.
39. As a distracted Mac user, I want to add more acceptable locations later, so that Faraday improves as I learn my environment.
40. As a distracted Mac user, I want the TUI to quit without stopping enforcement, so that strict sessions continue after closing the terminal.
41. As a distracted Mac user, I want the daemon to run manually during development, so that debugging is simple before launchd integration.
42. As a distracted Mac user, I want a user LaunchAgent later in the phase, so that Faraday can keep running and restart after crashes.
43. As a future contributor, I want the daemon API to be local and inspectable, so that TUI, tests, and future UI clients can control Faraday safely.
44. As a future contributor, I want enforcement to be isolated from terminal UI code, so that UI bugs do not disable enforcement.
45. As a future contributor, I want native macOS operations behind adapters, so that tests can verify behavior without locking the developer's Mac.
46. As a future contributor, I want simulation and BLE observation sources to share the same classifier/session path, so that tests cover real behavior.
47. As a future contributor, I want JSON/JSONL persistence, so that state and events are easy to inspect during MVP iteration.
48. As a future contributor, I want old `near`/`far` naming replaced with `forbidden`/`acceptable`, so that code matches the domain model.
49. As a future contributor, I want root LaunchDaemon serious mode deferred, so that the working MVP does not get blocked by GUI-session complexity.
50. As a future user, I want Faraday to be honest that it is behavioral weak-moment resistance, not adversarial endpoint security, so that expectations are clear.

## Implementation Decisions

- Archive the old v0 PRD and use this PRD as the next-phase source of truth.
- Rename domain language in code, tests, API, and UI from `near`/`far` to `forbidden`/`acceptable`.
- Keep the classification set small and stable: `forbidden`, `acceptable`, `uncertain`, and `missing`.
- Use session states that reflect product behavior: `idle`, `setupRequired`, `calibrationRequired`, `waitingForAcceptable`, `active`, `violationWarning`, `lockedAfterViolation`, `degradedBeaconTrust`, and `stopped`.
- Build a Swift daemon as the authority for sensing, classification, session state, persistence, event logging, overlay launching, session notifications, dry-run/armed enforcement, and native lock requests.
- Build a Swift native overlay helper as a separate process. The overlay has no enforcement authority; if it crashes, the daemon still owns countdown and lock decisions.
- Build a Bun TUI as the primary control surface. The TUI sends commands and displays state/events only; it never directly locks macOS and never owns session internals.
- Use a local Unix domain socket JSON-RPC API between TUI and daemon.
- Provide command families for status, session control, simulation, calibration, events, overlay testing, and dev-only shutdown.
- Include status fields for daemon uptime, active observation source, scanner status, enforcement mode, session state, proximity classification, calibration confidence, overlay/countdown state, last beacon seen, and recent events.
- Use JSON files for settings, calibration, and status; use JSONL for append-only events.
- Write settings, calibration, and status atomically; append events line-by-line.
- Support multiple observation sources running for visibility, but select exactly one authoritative source for classification at a time.
- Implement a simulated observation source first because hardware has not arrived. It must feed the same daemon path as real BLE.
- Implement simulation controls for direct classification injection and replayed scenarios.
- Implement real BLE as iBeacon-only scanning through CoreBluetooth. Do not claim generic BLE device support.
- Identify beacons by UUID, major, and minor. Device names are not authoritative.
- Provide scan-and-select setup for nearby iBeacon candidates, with manual identity entry fallback.
- Calibration model compares a forbidden phone area against an acceptable phone location set.
- Calibration requires at least one acceptable location; recommend three distinct acceptable locations for better confidence.
- Calibration sampling defaults to about 20 seconds per sample and should expose sample count, median, variance/noise, and live RSSI sparkline.
- Calibration confidence uses simple band separation: compare forbidden RSSI band and acceptable RSSI band, with median separation and overlap checks.
- Initial confidence thresholds: good at roughly 15 dB or more separation with low overlap, weak at roughly 8–14 dB, unusable below roughly 8 dB or heavy overlap.
- Armed enforcement is blocked unless beacon identity is configured, forbidden area is calibrated, at least one acceptable location is calibrated, and confidence is good.
- Dry-run enforcement is default. It records lock requests and shows warnings without locking macOS.
- Armed enforcement is explicit and visually obvious in both TUI and overlay.
- Use conservative classification: only classify forbidden when signal strongly matches the forbidden band for the sustain period; only classify acceptable when signal strongly matches acceptable band for the sustain period; otherwise classify uncertain.
- Uncertain proximity warns but does not lock and does not count as acceptable recovery.
- Initial timing defaults: forbidden sustain about 5 seconds, acceptable sustain about 15 seconds, missing timeout about 10 seconds, first violation countdown about 30 seconds, repeat/post-unlock countdown about 10–15 seconds.
- Missing beacon does not lock from missing alone. It creates a beacon-trust failure and marks the strict session degraded/invalid.
- Beacon-trust recovery requires seeing the beacon in the forbidden phone area again, then seeing acceptable proximity again before strict enforcement resumes.
- Native overlay should be large, always-on-top, and present across displays where feasible. It should dim the background, show countdown, classification, enforcement mode, and a clear instruction to move the phone to an acceptable location.
- Use a Faraday visual theme: near-black/graphite base, cyan/teal acceptable state, amber/red forbidden violation, violet/magenta degraded/missing warning, blue dry-run badge, red armed badge, field lines, electrical pulses, signal rings, and instrument-like telemetry.
- Use lightly themed violation copy, e.g. “Containment breach: phone detected in forbidden area. Move it to an acceptable location.”
- Native lock implementation starts with a `CGSession -suspend` adapter. The adapter logs attempts and failures and is replaceable later.
- Tests must use mock enforcement adapters so automated tests never lock the developer's Mac.
- Use macOS session/unlock notifications for clean post-unlock behavior in the user LaunchAgent context.
- On unlock/session-active after a violation lock, immediately evaluate current classification. Forbidden starts the repeat countdown; acceptable clears the violation; missing enters degraded trust; uncertain warns without locking.
- Defer root-owned LaunchDaemon serious mode. Next phase uses a user LaunchAgent only, because GUI overlay and session notifications are simpler and more reliable there.
- Defer Emergency Co-work Mode until after the core enforcement loop works.
- Launchd installation comes after the manual daemon/TUI/overlay loop works.
- Keep the full software local-first: no cloud account, no telemetry, no iOS app, no paid software features.

## Testing Decisions

- Test external behavior, not implementation details.
- Automated tests must never lock the developer's Mac.
- The calibrated classifier should be tested with synthetic RSSI sample streams for forbidden, acceptable, uncertain, noisy boundary, missing, and recovery scenarios.
- Calibration tests should verify confidence results from representative forbidden and acceptable sample sets, including good separation, weak separation, and unusable overlap.
- Session state machine tests should verify start requirements, waiting-for-acceptable activation, forbidden violation countdown, dry-run lock skip, armed lock request, missing-to-degraded behavior, and recovery through forbidden revalidation then acceptable proximity.
- Enforcement adapter tests should verify dry-run never calls native lock and armed mode calls the lock adapter only after countdown expiry.
- Overlay orchestration tests should verify the daemon requests overlay show/update/hide at the right externally visible states without requiring real UI rendering.
- JSON-RPC tests should verify command contracts, status shape, error handling, event tailing, and socket cleanup behavior.
- Persistence tests should verify atomic settings/calibration/status round trips and JSONL event append/load behavior.
- Simulation source tests should verify injected classifications and replay scenarios drive the same daemon behavior as other observation sources.
- BLE parser tests should verify iBeacon manufacturer data parsing and allowlist matching without requiring hardware.
- Manual BLE validation should be performed when the beacon arrives: scan/select, RSSI display, calibration, strict session activation, forbidden violation, overlay, armed lock, unlock repeat countdown, and missing degradation.
- TUI tests should focus on command wiring and render-state mapping where practical; avoid brittle snapshot tests for terminal art unless stable.
- LaunchAgent integration should use manual smoke tests first: install, start at login, KeepAlive restart after process kill, TUI reconnect, overlay availability, and clean removal.
- Existing Swift tests should be fixed or migrated so local test runs pass in the current toolchain.

## Out of Scope

- iOS companion app.
- Direct iPhone sensing without a beacon.
- Generic BLE device proximity support beyond iBeacon candidate discovery/debugging.
- AirTag, UWB, Wi-Fi/IP/mDNS/Bonjour distance estimation.
- Root-owned LaunchDaemon serious mode.
- Adversarial tamper resistance against a determined local admin.
- Emergency Co-work Mode for this next phase.
- Polished macOS menu bar app or SwiftUI dashboard.
- Cloud accounts, sync, teams, analytics, or telemetry.
- Ecommerce, fulfillment, branded beacon kit work, or paid software features.
- Treating simulation as final Working MVP evidence.
- Locking macOS from missing beacon alone.

## Further Notes

The next-phase implementation order should be:

1. Fix tests/toolchain and rename domain language from `near`/`far` to `forbidden`/`acceptable`.
2. Add calibrated classifier and confidence model.
3. Add daemon core and JSON/JSONL persistence.
4. Add Unix socket JSON-RPC.
5. Add simulation source and replay scenarios.
6. Add Bun TUI session dashboard.
7. Add native overlay helper.
8. Add dry-run/armed enforcement and the native lock adapter.
9. Add unlock/session notifications.
10. Add BLE iBeacon scanner and scan/select setup.
11. Add calibration wizard in the TUI.
12. Add user LaunchAgent install and smoke tests.
13. Run real-beacon validation when the parcel arrives.

Definition of done for this PRD:

- Tests pass locally.
- Daemon can run manually.
- TUI connects to daemon.
- Simulation drives the full strict-session loop: forbidden start, acceptable activation, forbidden violation, overlay countdown, dry-run lock skipped, armed lock path testable with explicit confirmation, and missing-to-degraded behavior.
- Calibration model exists and blocks armed mode when confidence is weak, unusable, or missing.
- BLE scanner can detect/select iBeacon hardware when available.
- Native lock works manually in armed mode.
- Unlock/session notification causes repeat countdown if still forbidden.
- JSON/JSONL logs record key events.
- User LaunchAgent install is documented and smoke-tested.
- Old v0 PRD is archived, and next implementation issues are created only after user approval.
