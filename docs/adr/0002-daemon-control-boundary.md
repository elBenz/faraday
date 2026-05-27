# ADR 0002: daemon-owned enforcement and local control API

- Status: Accepted
- Date: 2026-05-21
- Related PRD: `docs/PRD.md`

## Context

Faraday needs a terminal control surface for setup, calibration, status, and session control, but enforcement must continue if the terminal UI exits. Launchd should keep the enforcing process alive independently from any UI.

Options considered:

1. Put enforcement directly in the TUI process
2. Split daemon and TUI, with local file-based command exchange
3. Split daemon and TUI, with localhost HTTP API
4. Split daemon and TUI, with Unix domain socket JSON-RPC API

## Decision

Use a split architecture:

- `faradayd` daemon owns sensing, classification, session state, emergency timers, persistence, event logging, and native lock requests.
- `faraday` TUI sends commands and displays status/events only.
- The control API is local Unix domain socket JSON-RPC.

## Rationale

- Closing the TUI must not stop enforcement.
- Launchd can keep the daemon alive independently.
- A local socket avoids public TCP ports and port conflicts.
- JSON-RPC keeps commands inspectable and easy to exercise from tests or simple tools.
- Later menu bar or GUI surfaces can reuse the same daemon API.

## Consequences

- The daemon must expose stable command/status/event contracts.
- TUI code must not directly call native lock enforcement.
- Tests should cover daemon command handling separately from terminal rendering.
- Socket path, permissions, and stale-socket cleanup need explicit implementation.
