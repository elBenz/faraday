# Recommended Beacon Kit Viability Decision

## Scope

Evaluate whether Faraday should move from compatibility-list-only to a recommended third-party beacon kit. This is product strategy, not MVP software scope.

## Inputs reviewed

- `docs/MVP_VALIDATION.md` (manual validation harness + PRD success metrics)
- `docs/BEACONS.md` (compatibility evidence)
- `docs/PRD.md` and `docs/PRODUCT.md` (BYO-first and MVP boundaries)

## Current evidence snapshot (2026-05-21)

- Validation harness exists, but no completed 5-workday results are recorded yet.
- Compatibility list currently has no tested devices.
- Therefore there is not yet enough measured evidence to recommend a specific kit.

## Recommendation

**Defer recommended kit launch for now** and continue with **compatibility-list-only** until evidence thresholds are met.

This preserves bring-your-own beacon as a first-class path.

## Decision criteria to revisit

Re-open this decision once both are true:

1. At least one completed MVP validation run meets PRD success metrics.
2. At least two beacon models are marked **Tested** in `docs/BEACONS.md` with stable setup notes.

## If/when a kit is recommended: required follow-up work

- Support policy (setup support scope, SLA expectations)
- Warranty/replacement policy and failure handling
- Fulfillment workflow (inventory, shipping regions, returns)
- Setup materials (quick-start guide, reset/re-pair instructions, troubleshooting)
- Public compatibility matrix updates that keep BYO clearly supported

## Notes

- This decision does not change MVP software scope.
- No proprietary hardware requirement is introduced.
