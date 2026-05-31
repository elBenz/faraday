# MVP Validation Harness

This harness validates the Faraday Working MVP against `docs/specs/0001-working-mvp.md`, recovery-protection requirements in `docs/specs/0002-armed-mode-recovery-protection.md`, and the shared language in `CONTEXT.md`. It is for real-beacon evidence only; simulation is useful development evidence but does not complete the Working MVP.

## 1) Hardware setup checklist (phone-attached configurable iBeacon)

Record before testing:

- Date/time:
- Mac model + macOS version:
- Beacon model + firmware:
- Beacon battery status:

Checklist:

- [ ] Beacon is physically attached to phone or phone case (not carried separately).
- [ ] Beacon format is iBeacon.
- [ ] Beacon UUID is configured to Faraday target UUID.
- [ ] Beacon major/minor are configured and match Faraday allowlist.
- [ ] Beacon TX power and advertising interval are set per baseline profile.
- [ ] Faraday scanner can detect the beacon when phone is at desk.
- [ ] `firstValidatedBeacon` metadata observed for expected UUID/major/minor.
- [ ] Beacon still detected after normal phone handling (pick up, pocket, return).

## 2) Manual end-to-end session script

Run this full script at least once before daily usage tracking.

### A. Session start + acceptable activation

- [ ] Start strict session while beacon is in the forbidden phone area.
- [ ] Verify system enters `waitingForAcceptable` state.
- [ ] Move phone/beacon to the chosen acceptable phone location.
- [ ] Verify sustained acceptable proximity activates the session.

Result: pass / fail
Notes:

### B. Forbidden violation countdown + armed lock

- [ ] During active session, bring phone/beacon back into the forbidden phone area.
- [ ] Verify native overlay warning/countdown appears.
- [ ] Verify armed mode is explicit and visible.
- [ ] Keep beacon in forbidden proximity through countdown.
- [ ] Verify lock is requested and macOS session locks.

Result: pass / fail
Notes:

### C. Post-unlock recheck

- [ ] Unlock macOS while phone/beacon is still in the forbidden phone area.
- [ ] Verify Faraday immediately rechecks current classification.
- [ ] Verify repeat countdown starts with shorter post-unlock timing.
- [ ] Move phone/beacon to acceptable proximity before countdown expires.
- [ ] Verify violation clears and active session resumes.

Result: pass / fail
Notes:

### D. Missing-beacon degradation without lock

- [ ] Start active session from confirmed acceptable proximity.
- [ ] Make beacon missing beyond the missing timeout (e.g., shield/remove battery briefly).
- [ ] Verify beacon-trust failure/degraded state appears.
- [ ] Verify Faraday warns clearly and does **not** lock from missing alone.
- [ ] Restore beacon in the forbidden phone area to revalidate attachment/aliveness.
- [ ] Move phone/beacon back to acceptable proximity.
- [ ] Verify strict enforcement resumes only after acceptable recovery.

Result: pass / fail
Notes:

## 3) Five-workday usage review template

Use at least 5 workdays, with 2 strict sessions per day (minimum 10 sessions).

### Daily log

| Day | Session | Start/End | Duration (min) | Phone in forbidden phone area during strict session (min) | False lockout? | Beacon-trust failures? | Bypass attempt (kill/unload/uninstall)? | Notes |
| --- | --- | --- | ---: | ---: | --- | --- | --- | --- |
| 1 | AM |  |  |  |  |  |  |  |
| 1 | PM |  |  |  |  |  |  |  |
| 2 | AM |  |  |  |  |  |  |  |
| 2 | PM |  |  |  |  |  |  |  |
| 3 | AM |  |  |  |  |  |  |  |
| 3 | PM |  |  |  |  |  |  |  |
| 4 | AM |  |  |  |  |  |  |  |
| 4 | PM |  |  |  |  |  |  |  |
| 5 | AM |  |  |  |  |  |  |  |
| 5 | PM |  |  |  |  |  |  |  |

### Weekly totals

- Total sessions completed:
- Total strict-session forbidden-area minutes:
- False lockouts total:
- Beacon-trust failures total:
- Bypass attempts total:

## 4) PRD success metric pass/fail sheet

Mark pass/fail and include evidence pointer (log rows + relevant event timestamps).

| PRD success metric | Target | Observed | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- |
| Workdays completed | 5 days |  |  |  |
| Sessions per day | 2/day |  |  |  |
| Forbidden-area phone time during strict session | <= 2 minutes/session |  |  |  |
| False lockouts | < 1/day |  |  |  |
| Beacon-trust failures | Tracked; no native lock from missing alone |  |  |  |
| Bypass behavior | No kill/unload/uninstall during test period |  |  |  |

## 5) Feeding findings into GitHub follow-up issues

Create issues for any failures or reliability gaps.

Suggested issue format:

- Title: `Validation finding: <short label>`
- Include:
  - Environment (Mac + beacon)
  - Repro steps
  - Expected vs observed
  - Evidence (event log timestamps, daily table row)
  - Severity (blocks MVP / high / medium / low)
  - Proposed next action

Commands:

```bash
gh issue create --title "Validation finding: <short label>" --body-file <body.md>
gh issue view <number> --comments
```
