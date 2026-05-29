# PRD: Armed-mode Recovery Protection

## Problem Statement

Armed enforcement can currently lock macOS from a forbidden-proximity violation, but the recovery story is not safe enough for real-beacon validation. A CLI/TUI panic command is not a true fail-safe because it cannot help while the Mac is locked or when an overlay makes interaction confusing. The user needs Faraday to preserve weak-moment resistance without trapping them in unintended lock or overlay loops when the phone and computer must be close together.

## Solution

Add daemon-owned armed-mode recovery protection before continuing real-beacon armed validation. Armed enforcement gets a default timebox, post-unlock cooldown, repeat-lock countdown, and repeated-lock circuit breaker. The overlay becomes prominent but non-modal, never stealing keyboard or mouse interaction. Missing and uncertain proximity remain non-locking classifications. The TUI exposes a single guided setup flow plus dashboard state for armed time remaining, cooldowns, countdowns, circuit-breaker state, and recovery-protection pause reasons.

## User Stories

1. As a distracted Mac user, I want armed enforcement to be timeboxed during MVP validation, so that one experiment cannot leave native lock authority active longer than intended.
2. As a distracted Mac user, I want first real-beacon armed validation capped to about 5 minutes, so that testing real lock behavior feels safe.
3. As a distracted Mac user, I want armed timebox expiry to switch Faraday to dry-run, so that expired validation cannot lock my Mac.
4. As a distracted Mac user, I want armed timebox expiry to hide active violation countdown UI, so that the UI matches the new non-locking state.
5. As a distracted Mac user, I want timebox expiry logged, so that I can understand why enforcement mode changed.
6. As a distracted Mac user, I want a cooldown after unlocking from a Faraday lock, so that I regain immediate access to the computer.
7. As a distracted Mac user, I want post-unlock cooldown to last about 2 minutes, so that I can handle legitimate phone-and-computer-close moments.
8. As a distracted Mac user, I want cooldown to warn without locking, so that Faraday remains honest without trapping me.
9. As a distracted Mac user, I want acceptable proximity during cooldown to return the session to normal active enforcement, so that moving the phone away resolves the violation cleanly.
10. As a distracted Mac user, I want missing proximity during cooldown to degrade beacon trust without locking, so that BLE dropouts do not punish me.
11. As a distracted Mac user, I want uncertain proximity during cooldown to warn without locking, so that ambiguous RSSI never causes a native lock.
12. As a distracted Mac user, I want repeat locks to use a countdown, so that Faraday never instantly relocks after cooldown.
13. As a distracted Mac user, I want repeat countdowns to be shorter than the first violation countdown, so that repeated violations still create pressure without being silent.
14. As a distracted Mac user, I want repeat countdowns to cancel when acceptable proximity is sustained, so that moving the phone away always resolves the problem.
15. As a distracted Mac user, I want repeated lock requests to trip a circuit breaker, so that unstable calibration or placement cannot create a hostile lock loop.
16. As a distracted Mac user, I want the MVP circuit breaker threshold to be 2 lock requests within 10 minutes, so that the second lock proves instability and the third lock never happens automatically.
17. As a distracted Mac user, I want the circuit breaker to switch enforcement to dry-run, so that native lock authority is disabled after repeated lock requests.
18. As a distracted Mac user, I want the circuit breaker to hide active countdown UI, so that I can use the Mac normally after protection trips.
19. As a distracted Mac user, I want the circuit breaker to require explicit re-arm, so that Faraday cannot silently resume native lock authority.
20. As a distracted Mac user, I want the overlay to be prominent but non-modal, so that I notice violations without losing access to the desktop.
21. As a distracted Mac user, I want the overlay to never steal keyboard or mouse interaction, so that overlay bugs do not block recovery.
22. As a distracted Mac user, I want overlay copy to explain cooldown, countdown, and circuit-breaker state, so that I know what Faraday is doing.
23. As a distracted Mac user, I want the TUI dashboard to show armed time remaining, so that I know how long native lock authority remains active.
24. As a distracted Mac user, I want the TUI dashboard to show cooldown remaining, so that I know when repeat enforcement may resume.
25. As a distracted Mac user, I want the TUI dashboard to show circuit-breaker state, so that I know why armed enforcement is disabled.
26. As a distracted Mac user, I want `panic` language replaced or demoted, so that Faraday does not imply a CLI command is sufficient when the Mac is locked.
27. As a distracted Mac user, I want setup to be a single guided flow, so that installation, beacon selection, calibration, dry-run rehearsal, and armed validation are less tedious.
28. As a distracted Mac user, I want real-beacon armed validation paused until recovery protection exists, so that validation does not risk lock loops.
29. As a contributor, I want recovery protection owned by the daemon, so that closing the TUI does not change enforcement semantics.
30. As a contributor, I want recovery-protection logic tested with mock enforcement, so that automated tests never lock macOS.
31. As a future GUI developer, I want recovery-protection state exposed through the daemon API, so that a later menu-bar or native app can reuse the same safety model.

## Implementation Decisions

- Build a deep daemon-core recovery-protection module that owns armed timebox, post-unlock cooldown, repeat countdown, circuit breaker, and pause reasons behind a small state-transition API.
- Keep lock decisions daemon-owned. The TUI and any future GUI remain control/display surfaces only.
- Add recovery-protection state to persisted status and JSON-RPC status: armed expiry, cooldown expiry or remaining seconds, repeat countdown state, circuit-breaker state, lock request window, and pause reason.
- Add recovery-protection event kinds for armed timebox expiry, cooldown start/end, repeat countdown start/cancel/expire, circuit breaker trip, and explicit re-arm.
- Armed mode is timeboxed by default during MVP validation. First real-beacon armed validation has a 5 minute cap.
- Armed timebox expiry switches enforcement to dry-run, hides active countdown overlay, records an event, and requires explicit arming for any later native lock authority.
- Post-unlock recheck no longer immediately requests another lock. It enters a 2 minute cooldown when the prior lock was Faraday-caused.
- During post-unlock cooldown, forbidden proximity may warn but cannot lock. Acceptable proximity returns to active enforcement. Missing proximity degrades beacon trust. Uncertain proximity remains non-locking.
- After cooldown, if forbidden proximity is still sustained, Faraday starts a repeat countdown of about 10-15 seconds before requesting another lock.
- Repeated lock circuit breaker threshold is 2 lock requests within 10 minutes.
- Circuit breaker action is dry-run enforcement, hidden countdown overlay, visible paused-by-recovery-protection session state, explicit re-arm required.
- Do not implement a safe-mode sentinel file for MVP.
- Preserve missing/uncertain never-lock rules in all recovery-protection branches.
- Convert the overlay contract from a generic violation show/hide command toward stateful non-modal display updates that can render countdown, cooldown, armed time remaining, and circuit-breaker copy.
- The overlay must remain non-modal: prominent, always-on-top where feasible, visible across displays where feasible, but not stealing keyboard or mouse interaction.
- Update the TUI dashboard and guided setup flow to present recovery-protection state clearly.
- Guided setup flow order: health check, daemon/LaunchAgent state, beacon scan/select or manual entry, calibration, confidence display, dry-run rehearsal, explicit capped armed validation, dashboard/log handoff.
- Rename or demote user-facing `panic` framing. If a command remains, describe it as an unlocked recovery command, not a locked-screen fail-safe.
- Defer native GUI/menu-bar implementation. Design is tracked separately and must reuse the daemon API.

## Testing Decisions

- Test external behavior and state transitions, not implementation details.
- Automated tests must use mock enforcement adapters and must never call native macOS lock.
- Add daemon-core state-machine tests for armed timebox expiry, dry-run transition, overlay hide/update, and recovery-protection event emission.
- Add post-unlock cooldown tests for forbidden, acceptable, missing, and uncertain classifications.
- Add repeat countdown tests verifying no instant relock and cancellation on acceptable proximity.
- Add circuit-breaker tests verifying 2 lock requests within 10 minutes trips dry-run and explicit re-arm is required.
- Add no-lock classification regression tests proving missing and uncertain cannot trigger native lock in normal, cooldown, repeat-countdown, and circuit-breaker states.
- Add JSON-RPC/status tests proving recovery-protection fields are exposed and stable for TUI/future GUI clients.
- Add overlay adapter/orchestration tests proving countdown/cooldown/circuit-breaker state is shown or hidden at the right external states without rendering real UI.
- Add TUI render-state tests where practical for guided setup and recovery-protection dashboard mapping; avoid brittle terminal-art snapshots.
- Manual real-beacon validation resumes only after tests pass and the armed path is capped with recovery protection.

## Out of Scope

- Safe-mode sentinel file behavior.
- Adversarial tamper resistance against a determined local admin.
- Root LaunchDaemon serious mode.
- Native GUI or menu-bar implementation before Working MVP validation.
- Cloud accounts, telemetry, or phone-side app work.
- Locking from missing or uncertain proximity.
- Treating a CLI/TUI panic command as a locked-screen fail-safe.

## Further Notes

This PRD extends `docs/specs/0001-working-mvp.md` and the stable baseline in `docs/PRODUCT.md`. `faraday-alk.16` real-beacon validation now depends on this work because armed validation should not continue until recovery protection exists. A separate backlog issue tracks future native GUI/menu-bar design after the Working MVP proves the daemon API and core flows.
