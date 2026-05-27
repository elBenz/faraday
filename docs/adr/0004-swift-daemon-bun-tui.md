# ADR 0004: Swift daemon with Bun terminal UI

- Status: Accepted
- Date: 2026-05-21

## Context

Faraday needs native macOS capabilities for BLE scanning, overlays, session locking, and launchd integration. It also needs a high-quality terminal control surface for setup, calibration, session status, and simulation. Building a polished TUI in Swift may slow iteration.

Options considered:

1. Pure Swift daemon, overlay, and TUI
2. Swift daemon/overlay with Bun TUI over local control API
3. Simple Swift CLI first, richer TUI later

## Decision

Use a Swift daemon/overlay for native macOS behavior and a Bun-based TUI as the primary terminal control surface.

- Swift `faradayd` owns sensing, classification, session state, persistence, overlay launching, and lock enforcement.
- Swift `faraday-overlay` owns native warning UI.
- Bun `faraday` TUI talks to `faradayd` through the local Unix domain socket JSON-RPC API.

## Rationale

- Native macOS work remains in Swift.
- TUI iteration can be faster and more polished in Bun.
- The daemon API keeps UI replaceable; a future menu bar app can reuse the same protocol.
- Separate processes keep enforcement independent from the terminal UI.

## Consequences

- The repo now has two runtime stacks: Swift and Bun.
- JSON-RPC protocol contracts need tests/fixtures.
- TUI must remain non-authoritative: it never directly locks the Mac and never owns session state.
- Packaging must eventually account for Bun/runtime or compile/bundle the TUI path.
