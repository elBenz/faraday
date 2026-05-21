# MVP Validation Harness

This harness validates Faraday against the PRD success metrics in real-world use.

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

### A. Session start + far activation

- [ ] Start strict session while beacon is near.
- [ ] Verify system enters waiting-for-far state.
- [ ] Move phone/beacon to target room.
- [ ] Verify sustained far confirmation activates session.

Result: pass / fail
Notes:

### B. Near violation countdown + lock

- [ ] During active session, bring phone/beacon back near desk.
- [ ] Verify warning/countdown appears.
- [ ] Keep beacon near through countdown.
- [ ] Verify lock is requested and macOS session locks.

Result: pass / fail
Notes:

### C. Missing-beacon grace + lock

- [ ] Start active session from confirmed far state.
- [ ] Make beacon temporarily missing (e.g., shield/remove battery briefly).
- [ ] Verify grace/warning behavior first.
- [ ] Keep beacon missing beyond grace window.
- [ ] Verify lock is requested after grace expiry.

Result: pass / fail
Notes:

### D. Emergency Co-work Mode

- [ ] Request emergency mode with reason.
- [ ] Verify pending delay then activation.
- [ ] Verify lock requests are suppressed while emergency is active.
- [ ] Use one extension and verify it succeeds.
- [ ] Attempt second extension and verify refusal.
- [ ] Verify expiration requires far recovery before lock enforcement resumes.

Result: pass / fail
Notes:

## 3) Five-workday usage review template

Use at least 5 workdays, with 2 strict sessions per day (minimum 10 sessions).

### Daily log

| Day | Session | Start/End | Duration (min) | Phone-at-desk during strict session (min) | False lockout? | Emergency used? | Bypass attempt (kill/unload/uninstall)? | Notes |
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
- Total strict-session phone-at-desk minutes:
- False lockouts total:
- Emergency activations total:
- Bypass attempts total:

## 4) PRD success metric pass/fail sheet

Mark pass/fail and include evidence pointer (log rows + relevant event timestamps).

| PRD success metric | Target | Observed | Pass/Fail | Evidence |
| --- | --- | --- | --- | --- |
| Workdays completed | 5 days |  |  |  |
| Sessions per day | 2/day |  |  |  |
| Phone-at-desk during strict session | <= 2 minutes/session |  |  |  |
| False lockouts | < 1/day |  |  |  |
| Emergency usage | <= 2/week |  |  |  |
| Bypass behavior | No kill/unload/uninstall during test period |  |  |  |

## 5) Feeding findings into Beads follow-up issues

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
bd create "Validation finding: <short label>"
bd show <new-id>
```
