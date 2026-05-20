# Agent Guide

## Project

Faraday: macOS focus enforcement. Mac locks when phone-attached BLE beacon is too near during strict focus session.

Primary product spec: `docs/PRD.md`.

## Work rules

- Keep MVP local-first: no cloud, no accounts, no iOS app.
- Treat beacon as sensed object, not iPhone directly.
- Prefer testable core logic over UI polish.
- Separate BLE scanning, RSSI classification, session state machine, enforcement adapter, calibration, persistence.
- Never let automated tests lock developer Mac; mock enforcement adapter.
- Do not commit secrets, local scratch, or agent automation state.

## Implementation direction

- Target native Swift macOS app/daemon.
- Use CoreBluetooth for beacon observations.
- Use launchd for startup/keepalive later.
- Default behavior should be configurable and calibration-overridable.
- Enforcement target: weak-moment resistance, not adversarial security against local admin.

## Docs

- Update `docs/PRD.md` when product behavior or scope changes.
- Add ADRs under `docs/adr/` for major architecture decisions once implementation starts.
