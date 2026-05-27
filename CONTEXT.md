# Faraday Context

Faraday is a local-first macOS focus enforcement product that keeps a phone-attached beacon physically away during strict focus work.

## Language

**Open-source app**:
The full Faraday macOS software product whose source code is public under an open-source license.
_Avoid_: Open core, source-available app

**Compatibility list**:
A public list of tested BLE beacons and recommended settings for Faraday.
_Avoid_: Required hardware, official-only hardware

**Future beacon kit**:
A possible later paid bundle containing a compatible BLE beacon, setup materials, and convenience onboarding for Faraday.
_Avoid_: Current MVP requirement, proprietary dongle

**Paid convenience**:
Productized non-software help around Faraday, such as a preconfigured beacon, setup materials, onboarding, support, and warranties.
_Avoid_: Paywalled software features, subscription requirement, paid calibration presets

**Bring-your-own beacon**:
A user-supplied compatible iBeacon that Faraday supports as a first-class setup path.
_Avoid_: Unsupported beacon, unofficial beacon

**Apache-2.0 license**:
The open-source license for the Faraday software, chosen for permissive reuse with explicit patent terms.
_Avoid_: Proprietary license, source-available license

**Product strategy**:
The separate commercialization plan for selling a beacon kit and paid convenience around the open-source app.
_Avoid_: MVP requirements, hardware design spec

**Working MVP**:
A real strict session that runs end-to-end on the user's Mac with a real phone-attached beacon: configured beacon identity, near start confirmation, far activation, near violation warning, native Mac lock, post-unlock recheck, local event logging, and automated tests that never lock the developer's Mac.
_Avoid_: Simulated-only demo, UI-only prototype, documentation-only milestone

**Almost-working MVP**:
A near-complete strict-session flow with at most one dev shortcut, such as CLI control instead of polished UI or a basic overlay instead of final UI polish. Real BLE sensing and real lock enforcement still exist.
_Avoid_: Simulated BLE, no-op lock enforcement

**Chosen phone location**:
A user-selected acceptable place where the phone-attached beacon may stay during a strict session. It may be another room, hallway, shelf, drawer, or farther-away spot in the same room if validation shows enough RSSI separation. Users may calibrate one acceptable location, but three distinct acceptable locations gives better confidence.
_Avoid_: Required target room, fixed shelf, prescribed storage place

**Forbidden phone area**:
The area where the phone must not be during a strict session, usually the desk or within easy reach. Calibration compares this area against acceptable phone locations.
_Avoid_: Any place with weak RSSI, vague "near" without user meaning

**Acceptable phone location set**:
One or more user-calibrated places where the phone may live during a strict session. Faraday uses the set to learn an acceptable RSSI range and warn if separation from the forbidden phone area is too weak.
_Avoid_: Single mandatory location, hardcoded room model

**Acceptable proximity**:
A trusted classification meaning the beacon signal matches the user-calibrated acceptable phone location set for long enough. This replaces "far" language in user-facing text and code.
_Avoid_: Required physical distance, required other room, uncalibrated weak signal

**Forbidden proximity**:
A trusted classification meaning the beacon signal matches the user-calibrated forbidden phone area for long enough. This replaces "near" language in user-facing text and code.
_Avoid_: Generic closeness, uncalibrated strong signal without user meaning

**Simulated observation source**:
A development-only source of proximity observations used before real beacon hardware is available. It feeds the same daemon, state machine, TUI, persistence, and enforcement paths as the real BLE source.
_Avoid_: Separate demo path, fake MVP evidence, replacement for real beacon validation

**Dry-run enforcement**:
The default enforcement mode where Faraday records lock requests and shows warnings without locking macOS. Used for development, simulation, and early validation.
_Avoid_: Successful real-lock validation, armed enforcement

**Armed enforcement**:
An explicit enforcement mode where Faraday may perform a native macOS lock when strict-session rules require it. It requires configured beacon identity, calibrated forbidden phone area, at least one calibrated acceptable phone location, sufficient calibration confidence, and explicit user arming. The UI must make this state obvious.
_Avoid_: Default mode, hidden lock behavior, uncalibrated native lock

**Beacon-trust failure**:
A state where Faraday cannot see the configured beacon long enough that proximity can no longer be trusted. Faraday warns clearly, marks the strict session degraded/invalid, and does not lock from missing alone. Recovery requires revalidating the beacon near the desk, then moving it back to the chosen phone location before strict enforcement resumes.
_Avoid_: Treating absence as proof of far, silent fail-open, fake protection, locking from missing alone, auto-resuming from far after signal returns

## Relationships

- The **Open-source app** is released under the **Apache-2.0 license**.
- The **Open-source app** supports a **Bring-your-own beacon** as a first-class path.
- The **Open-source app** documents compatible hardware through a **Compatibility list** first.
- A **Future beacon kit** can later package **Paid convenience** but is not required to use the **Open-source app**.
- **Paid convenience** must not paywall any software feature.
- All software features in the **Open-source app** stay free.
- **Product strategy** belongs in `docs/PRODUCT.md`, while software behavior belongs in `docs/PRD.md`.

## Example dialogue

> **Dev:** "Does Faraday require buying the **Beacon kit**?"
> **Domain expert:** "No — the **Open-source app** should work well with a **Bring-your-own beacon**, while the **Beacon kit** is the paid easy path."

## Flagged ambiguities

- "Open source and product to sell later" resolved as: full software is an **Open-source app**; near-term hardware strategy is a **Compatibility list**, and later monetization may come from an optional **Future beacon kit** and **Paid convenience**.
- "Official beacon" rejected as primary framing; resolved: **Bring-your-own beacon** is first-class, not merely tolerated.
- "Product to sell later" resolved as **Product strategy**, not core MVP scope.
