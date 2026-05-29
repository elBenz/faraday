# ADR 0003: dry-run default enforcement

- Status: Accepted
- Date: 2026-05-21
- Related spec: `docs/specs/0001-working-mvp.md`

## Context

Faraday's enforcement path can lock the user's Mac. During development, simulation, classifier tuning, and early beacon validation, accidental or repeated locks would slow work and reduce trust. Automated tests must never lock the developer's Mac.

Options considered:

1. Always use real native lock once enforcement code exists
2. Compile-time test mocks only, real app always locks
3. Runtime enforcement modes: dry-run by default, explicit armed mode for real lock

## Decision

Use runtime enforcement modes:

- **Dry-run enforcement** is the default. It records lock requests and shows warnings, but does not lock macOS.
- **Armed enforcement** must be explicitly enabled before Faraday can perform native macOS lock.

The TUI must make armed status obvious.

## Rationale

- Safe default while real beacon hardware is not yet available.
- Same daemon path can be exercised in simulation without risk.
- Users can validate classification and event logs before allowing lock.
- Working MVP still requires manual validation of armed native lock.

## Consequences

- Enforcement mode becomes persisted settings/state.
- Status output must always include enforcement mode.
- Event logs should distinguish lock requested from native lock executed or skipped due to dry-run.
- Tests should verify dry-run does not call native lock and armed mode does.
