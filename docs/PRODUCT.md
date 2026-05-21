# Faraday Product Strategy

Faraday is an open-source macOS focus enforcement app. The software remains free and open source; commercialization comes from hardware convenience, setup help, and support around compatible BLE beacons.

## Open-source posture

- Release the full macOS app/daemon as open source.
- Use the Apache-2.0 license.
- Keep all software features free.
- Do not paywall focus enforcement, calibration, emergency mode, installer behavior, or compatibility support inside the app.
- Preserve local-first behavior: no cloud account, subscription, telemetry, or required online service for core use.

## Hardware strategy

Faraday should support bring-your-own compatible iBeacons as a first-class path. Hardware sales must improve convenience, not create lock-in.

### Stage 1 — Compatibility list

Near-term strategy: publish a compatibility list instead of selling hardware.

- Test common configurable BLE/iBeacon devices.
- Document recommended UUID, major/minor, transmit power, advertising interval, battery expectations, and mounting guidance.
- Clearly distinguish tested, likely-compatible, and unsupported devices.
- Keep setup possible for users who buy their own beacon.

### Stage 2 — Recommended Beacon Kit

If demand appears, sell a curated kit using third-party beacon hardware.

- Bundle a tested beacon with setup materials.
- Prefer preconfigured or easy-to-configure settings.
- Sell convenience, reliability, and reduced setup friction.
- Continue supporting bring-your-own beacons.
- Gate this stage on the viability decision document in `docs/BEACON_KIT_VIABILITY.md`.

### Stage 3 — Faraday Beacon Kit

If usage and support volume justify it, consider a branded hardware bundle.

- Treat this as a later product decision, not MVP scope.
- Only pursue if it materially improves setup, reliability, or user trust.
- Avoid making branded hardware mandatory for the open-source app.

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
