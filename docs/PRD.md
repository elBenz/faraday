# PRD: Faraday

## Problem Statement

The user works on a Mac but repeatedly gets derailed by using their iPhone while trying to focus. Existing focus tools are too easy to bypass because they rely on intention, app limits, or friction inside the phone. The needed outcome is physical discipline: during a focus session, the iPhone must be physically far away from the desk, or the Mac should become unusable until the phone is moved away again.

A Mac-only solution that polls the iPhone directly is not technically reliable without an iOS companion app, because locked iPhones do not provide a stable, queryable proximity signal to arbitrary macOS software. The product therefore uses a small BLE beacon physically attached to the iPhone/case as the proximity signal. The Mac scans the beacon, estimates proximity from RSSI, and enforces focus-session rules locally.

## Solution

Build a native macOS focus daemon/app that enforces a strict focus session using a BLE iBeacon attached to the iPhone.

Before a strict session starts, the app confirms the beacon is alive and near the Mac. The user then physically moves the phone/beacon to another room. Once the beacon RSSI remains weak long enough, the session becomes active and the Mac remains usable.

During the active session, the daemon continuously scans for the beacon:

- If the beacon becomes near for a sustained period, the app shows a countdown overlay asking the user to move the phone away.
- If the phone remains near after the countdown, the daemon locks the macOS user session.
- If the beacon disappears briefly after previously being far, the app warns but allows a grace window.
- If the beacon stays missing too long during a strict session, the daemon treats the state as unsafe and locks the Mac.
- If the user has a real urgent need to use phone + Mac together, they can enter a short, logged Emergency Co-work Mode with limited duration and extension count.

The MVP targets personal macOS use first. It prioritizes behavioral effectiveness and robust local enforcement over dashboard polish, cloud features, or perfect anti-tamper security.

## User Stories

1. As a distracted Mac user, I want my Mac to require my phone to be physically away from my desk, so that I cannot keep checking my phone while working.
2. As a distracted Mac user, I want the system to use a hardware beacon attached to my phone, so that the Mac can detect phone proximity without needing an iOS app.
3. As a distracted Mac user, I want to start a strict focus session manually, so that enforcement only applies when I intentionally begin deep work.
4. As a distracted Mac user, I want the app to confirm the beacon is near before session setup starts, so that I know the beacon is alive and attached.
5. As a distracted Mac user, I want the app to tell me to move my phone away before the session begins, so that the required behavior is clear.
6. As a distracted Mac user, I want the session to become active only after my phone stays far away long enough, so that transient Bluetooth noise does not falsely approve the session.
7. As a distracted Mac user, I want the app to lock my Mac if my phone comes back near the desk, so that grabbing my phone breaks the work loop immediately.
8. As a distracted Mac user, I want a visible warning countdown before lock, so that accidental proximity can be corrected without a surprise lock.
9. As a distracted Mac user, I want the Mac to re-check phone proximity after unlock, so that unlocking the Mac does not bypass the session.
10. As a distracted Mac user, I want the Mac to relock if my phone is still near after I unlock, so that enforcement continues after the system lock screen.
11. As a distracted Mac user, I want the app to warn me when the beacon disappears, so that I know the sensor state is suspicious or unreliable.
12. As a distracted Mac user, I want a short missing-beacon grace period after the phone was confirmed far, so that Bluetooth drops do not instantly lock me out.
13. As a distracted Mac user, I want missing beacon at session startup to prevent session start, so that I cannot start a strict session while the beacon is absent.
14. As a distracted Mac user, I want missing beacon after being near to trigger unsafe behavior, so that removing or killing the beacon is not an easy bypass.
15. As a distracted Mac user, I want defaults that work without calibration, so that I can try the system quickly.
16. As a distracted Mac user, I want optional guided calibration, so that the app can adapt to my Mac, beacon, room layout, and desk.
17. As a distracted Mac user, I want calibration to measure desk, doorway, and target room RSSI, so that near/far thresholds are based on real environment data.
18. As a distracted Mac user, I want the app to show current classification, so that I understand whether the phone is near, far, uncertain, or missing.
19. As a distracted Mac user, I want the app to avoid aggressive lock/unlock flapping, so that Bluetooth noise does not ruin work.
20. As a distracted Mac user, I want hysteresis and sustained-time rules, so that the app reacts to real proximity changes rather than single RSSI spikes.
21. As a distracted Mac user, I want emergency access when I genuinely need phone and Mac together, so that the tool does not block real life.
22. As a distracted Mac user, I want Emergency Co-work Mode to be short and logged, so that it helps emergencies without becoming a normal bypass.
23. As a distracted Mac user, I want one limited emergency extension, so that real urgent tasks can finish without opening unlimited loopholes.
24. As a distracted Mac user, I want emergency mode to end by requiring the phone to be far again, so that normal enforcement resumes cleanly.
25. As a distracted Mac user, I want local logs of sessions, violations, missing-beacon events, locks, and emergencies, so that I can inspect whether the tool is working.
26. As a distracted Mac user, I want the daemon to run automatically after login/reboot, so that enforcement is not forgotten.
27. As a distracted Mac user, I want the daemon to restart if it crashes, so that enforcement remains active during sessions.
28. As a distracted Mac user, I want the daemon to be harder to kill casually, so that weak-moment bypass requires meaningful effort.
29. As a distracted Mac user, I want the MVP to work without cloud accounts, subscriptions, or an iOS app, so that it is cheap and private to build and use.
30. As a distracted Mac user, I want the beacon to be a common configurable iBeacon, so that the prototype can use off-the-shelf hardware.
31. As a distracted Mac user, I want the app to support beacon identifier allowlisting, so that nearby unrelated BLE devices do not affect enforcement.
32. As a distracted Mac user, I want the app to expose enough status for a future dashboard, so that focus stats can be added later without changing enforcement logic.
33. As a future contributor, I want enforcement logic separated from BLE scanning, so that the state machine can be tested without Bluetooth hardware.
34. As a future contributor, I want the lock mechanism abstracted behind an interface, so that tests can verify lock decisions without locking the developer's Mac.
35. As a future contributor, I want calibration data modeled separately from live RSSI observations, so that threshold logic remains simple and testable.
36. As a future contributor, I want launchd integration documented, so that the daemon can be installed, restarted, and removed predictably.
37. As a future user, I want clear language that this is B-level anti-bypass, not impossible security, so that expectations are honest.

## Implementation Decisions

- Build the core as a native Swift macOS daemon/app for robustness.
- Use CoreBluetooth for BLE scanning.
- Target configurable iBeacon hardware for the first prototype.
- Identify the phone-attached beacon by UUID plus major/minor, not by Bluetooth device name.
- Treat the iPhone itself as out of scope for sensing. The beacon attached to the iPhone/case is the sensed object.
- Do not build an iOS app for MVP.
- Do not rely on paired iPhone Bluetooth RSSI, iPhone MAC address, Wi-Fi ping, local IP reachability, Bonjour, or AirTag ecosystem behavior.
- Use a strict session state machine as the enforcement core.
- Session start flow:
  - User clicks Start Focus.
  - Daemon confirms beacon is currently near and alive.
  - UI instructs user to move phone to another room.
  - Daemon waits until the beacon is classified far for a sustained period.
  - Session becomes active only after far confirmation.
- Initial classification defaults:
  - Near: smoothed RSSI stronger than about `-65 dBm` for 30 seconds.
  - Far: smoothed RSSI weaker than about `-78 dBm` for 90 seconds.
  - Missing: no matching beacon advertisements for 10 seconds.
  - Uncertain: between near and far thresholds.
- Defaults must be configurable and replaced by calibration values when available.
- Use exponential moving average smoothing over RSSI observations.
- Use hysteresis: near and far thresholds differ, and far clearance requires longer sustained evidence than near violation.
- Near violations should trigger faster than far approvals.
- Missing beacon policy during strict session:
  - Missing immediately after near or unknown state is unsafe.
  - Missing after far-confirmed state enters warning/grace.
  - Missing beyond configured grace becomes unsafe and triggers lock behavior.
- Missing beacon outside strict session produces warning/status only.
- Use overlay countdown before native lock.
- Enforcement sequence:
  - Detect unsafe state.
  - Show overlay/countdown for about 30 seconds.
  - Continue scanning during countdown.
  - Cancel countdown if phone becomes far-confirmed again.
  - If unsafe persists, lock the macOS user session.
  - After unlock, immediately re-evaluate state and relock if still unsafe.
- Prefer native session lock over overlay-only enforcement.
- Overlay is a warning and UX layer, not the security boundary.
- Use launchd for automatic startup and KeepAlive in MVP.
- Serious personal-use mode should install as a root-owned LaunchDaemon requiring admin action to unload.
- Accept that perfect enforcement is impossible when the user is local admin.
- Design target is weak-moment resistance, not adversarial security.
- Emergency Co-work Mode:
  - User selects reason.
  - User waits 30–60 seconds.
  - App grants 10 minutes of phone + Mac coexistence.
  - One 10-minute extension allowed.
  - Emergency events are logged.
  - After expiration, the phone must become far again before the session can continue.
- Calibration UX:
  - Defaults available if user skips calibration.
  - Optional guided calibration measures phone on desk, phone at doorway/hall, and phone in target room.
  - Calibration produces near/far thresholds and confidence notes.
- Deep modules to build:
  - Beacon scanner: converts CoreBluetooth observations into timestamped RSSI samples for the configured beacon.
  - RSSI classifier: converts samples into near/far/uncertain/missing using smoothing, hysteresis, and timers.
  - Session state machine: converts classifications and user actions into session states and enforcement commands.
  - Enforcement adapter: executes overlay and native lock commands behind a testable interface.
  - Calibration engine: records guided RSSI samples and derives thresholds.
  - Persistence/logging module: stores settings, calibration, session events, emergency events, and violations.
  - Launchd installer/config module: installs and manages daemon startup behavior.
  - Status API: exposes current daemon state to local UI or future dashboard.

## Testing Decisions

- Test external behavior, not implementation details.
- Do not require BLE hardware for most automated tests.
- The RSSI classifier should be tested with synthetic timestamped observations.
- The session state machine should be tested with classification events and user actions.
- The enforcement adapter should be mocked in tests so test runs never lock the real Mac.
- Calibration should be tested with representative sample sets for desk, doorway, and target room.
- Logging should be tested by verifying emitted event records for major transitions.
- Launchd installation should have smoke/manual tests first; full automated tests may be deferred.
- CoreBluetooth scanner should have manual/integration tests with a real configured iBeacon.
- Good classifier tests include:
  - near sustained for threshold duration becomes near.
  - brief near spike does not become near.
  - far sustained for threshold duration becomes far.
  - missing after far enters grace.
  - missing after near becomes unsafe.
  - noisy boundary RSSI does not flap rapidly.
- Good state machine tests include:
  - session cannot start when beacon missing.
  - session starts only after near-confirmation then far-confirmation.
  - active session locks after sustained near violation.
  - active session warns during missing grace.
  - active session locks after missing grace expires.
  - emergency mode suppresses lock only for configured duration.
  - emergency extension works once and then refuses further extension.
  - post-lock unlock rechecks state and relocks when unsafe.
- MVP success metrics:
  - Five workdays of usage.
  - Two sessions per day.
  - Phone does not remain on desk for more than two minutes during a strict session.
  - False lockouts fewer than one per day.
  - Emergency mode used no more than twice per week.
  - User does not kill, unload, or uninstall daemon during test period.

## Out of Scope

- iOS companion app.
- Screen Time, FamilyControls, or ManagedSettings integration.
- Polling the iPhone directly over Bluetooth.
- Assuming a paired iPhone can be reliably pinged for fresh RSSI while locked.
- Wi-Fi/IP/mDNS/Bonjour distance estimation.
- AirTag support.
- UWB support.
- Next.js dashboard for MVP.
- Cloud accounts, sync, teams, or analytics.
- Cross-platform support.
- Commercial hardware design.
- Perfect anti-tamper enforcement against a determined local admin.
- Blocking specific iPhone apps.
- Managing phone notifications.
- Replacing a physical phone lockbox for adversarial self-control cases.

## Further Notes

Brick validates the physical-key/distraction-blocking product category, but it uses an iOS/Android app plus a physical device. This PRD chooses a different architecture: Mac-side enforcement plus a phone-attached BLE beacon. The beacon is required because macOS cannot reliably infer locked iPhone distance without phone cooperation.

The critical product truth is behavioral, not only technical. BLE detection working in isolation is not sufficient. The MVP succeeds only if it prevents phone-at-desk behavior during real work sessions without causing so many false lockouts that the user removes the tool.

Recommended first hardware purchase: configurable coin/button iBeacon with custom UUID, adjustable transmit power, adjustable advertising interval, and replaceable or rechargeable battery.

Recommended first prototype name: Faraday.
