# Faraday Product

Faraday is a local-first macOS focus enforcement product. It keeps a phone-attached BLE beacon out of the user's forbidden phone area during strict focus sessions.

`docs/PRODUCT.md` is the stable product baseline. Feature PRDs live in `docs/specs/`. Do not use a single global PRD file as the source of truth.

## Product principles

- Local-first: no cloud account, subscription, telemetry, or required online service for core use.
- Beacon-based: treat the BLE beacon as the sensed object; do not claim direct iPhone sensing.
- Weak-moment resistance: interrupt casual phone checking; do not promise adversarial security against a determined local admin.
- User-calibrated meaning: enforce forbidden and acceptable phone locations, not generic distance.
- Dry-run first: native lock enforcement is never the default.
- Daemon authority: sensing, classification, session state, overlay orchestration, persistence, and lock decisions belong to the daemon, not the UI.
- Test safety: automated tests must never lock the developer's Mac.

## Current product shape

Faraday is built from three cooperating local processes:

- Swift daemon: BLE sensing, calibrated classification, session state, persistence, overlay orchestration, local JSON-RPC API, and lock enforcement.
- Swift overlay helper: prominent non-modal warning UI.
- Bun TUI: setup, calibration, status, simulation, session control, and logs through the daemon API.

Future GUI or menu-bar surfaces may reuse the same daemon API, but must not own enforcement decisions.

## Core behavior baseline

- A strict session starts only after Faraday confirms the configured beacon is alive in the forbidden phone area.
- The session becomes active only after the beacon reaches acceptable proximity.
- Forbidden proximity during an active session shows a prominent non-modal overlay and starts a countdown.
- Armed enforcement may lock macOS only after explicit arming, eligible calibration, sustained forbidden proximity, and countdown expiry.
- Missing beacon creates a beacon-trust failure and never locks by itself.
- Uncertain proximity warns but never locks and does not count as acceptable recovery.
- Armed-mode recovery protection is required before real-beacon armed validation: timebox, post-unlock cooldown, repeat-lock countdown, repeated-lock circuit breaker, and clear UI state.

## Hardware and commercialization posture

Faraday software is open source. Commercialization, if any, comes from hardware convenience, setup help, and support around compatible BLE beacons.

### Open-source posture

- Release the full macOS app/daemon as open source.
- Use the Apache-2.0 license.
- Keep all software features free.
- Do not paywall focus enforcement, calibration, recovery protection, installer behavior, or compatibility support inside the app.

### Hardware strategy

Faraday supports bring-your-own compatible iBeacons as a first-class path. Hardware sales must improve convenience, not create lock-in.

1. Compatibility list: test common configurable BLE/iBeacon devices and document recommended settings.
2. Recommended Beacon Kit: optional curated third-party beacon bundle if demand appears.
3. Faraday Beacon Kit: possible later branded bundle only if it materially improves setup, reliability, or user trust.

## Documentation model

- `docs/PRODUCT.md`: stable product baseline and product strategy.
- `CONTEXT.md`: glossary only; terms, relationships, and avoid-language.
- `docs/specs/`: feature PRDs and major-change specs.
- `docs/adr/`: hard-to-reverse architecture decisions with trade-offs.
- GitHub Issues: small vertical implementation slices linked to durable specs.

## Active specs

- `docs/specs/0001-working-mvp.md` — Working MVP feature PRD.
- `docs/specs/0002-armed-mode-recovery-protection.md` — Armed-mode recovery protection feature PRD.

## Product boundaries

In scope for future productization:

- Compatibility documentation
- Setup guides
- Optional beacon bundles
- Onboarding/support materials
- Warranty/replacement policy for sold kits

Out of scope for the current software MVP:

- Ecommerce
- Fulfillment
- Custom hardware design
- Required proprietary beacon
- Paid software features
- Cloud accounts or subscriptions
- Native GUI or menu-bar implementation before Working MVP validation
