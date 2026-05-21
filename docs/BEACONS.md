# Beacon Compatibility

Faraday supports bring-your-own compatible BLE/iBeacon hardware as a first-class setup path. This document tracks tested devices and recommended settings.

## Compatibility goals

A good Faraday beacon should support:

- Configurable iBeacon UUID
- Configurable major/minor identifiers
- Adjustable transmit power
- Adjustable advertising interval
- Replaceable or rechargeable battery
- Physical attachment to a phone or phone case

## Recommended starting profile

Use these settings as an initial baseline until real-device testing refines them:

- Format: iBeacon
- Identifier: custom UUID plus major/minor allowlist
- Advertising interval: stable enough for repeated RSSI samples without excessive battery drain
- Transmit power: low-to-medium, tuned during calibration
- Placement: attached to phone or phone case, not carried separately

## Tested devices

No devices tested yet.

| Device | Status | Notes |
| ------ | ------ | ----- |
| TBD | Untested | Add device after manual BLE validation |

## Status labels

- **Tested** — validated with Faraday scanner, classifier, and a real strict focus session.
- **Likely compatible** — has required iBeacon configuration features but has not completed validation.
- **Unsupported** — missing required iBeacon configuration or too unreliable for enforcement.

## Validation checklist

For each candidate beacon:

- [ ] Can configure UUID, major, and minor.
- [ ] Can be detected by macOS/CoreBluetooth.
- [ ] Emits stable enough RSSI at desk distance.
- [ ] Emits weak enough RSSI from the target room.
- [ ] Survives normal phone movement and pocket/case placement.
- [ ] Battery life is acceptable for daily use.
- [ ] Documentation includes setup/reset steps.

## Manual scanner validation notes (allowlist)

Use this flow to validate the beacon allowlist scanner against a real configurable iBeacon:

1. Configure one beacon to the target UUID + major + minor.
2. Configure a second beacon to a different major/minor under the same UUID.
3. Start scanner and observe emitted `BeaconObservation` values.
4. Confirm only the allowlisted identifier emits observations.
5. Stop scanner and confirm no new observations are emitted while advertisements continue.
6. Record desk and target-room RSSI ranges for later classifier tuning.

## Product boundary

This compatibility list comes before selling hardware. Future recommended or branded beacon kits may package convenience, but Faraday must remain usable with compatible bring-your-own beacons.
