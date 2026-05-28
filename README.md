# Faraday

Faraday is an Apache-2.0 open-source macOS focus enforcement app. During a strict focus session, the Mac locks when a phone-attached BLE beacon is too near for too long.

The app senses a BLE beacon attached to the phone or phone case, not the iPhone directly. Bring-your-own compatible iBeacons are a first-class setup path.

## Product posture

- Full software app stays free and open source.
- Core enforcement never requires paid software features, cloud accounts, subscriptions, or proprietary hardware.
- Near-term hardware plan: publish a compatibility list for tested configurable iBeacons.
- Later product path: optional recommended beacon kit, then possible branded Faraday Beacon Kit if demand justifies it.

See [`docs/PRODUCT.md`](docs/PRODUCT.md).

## Quickstart

```bash
./faraday setup --yes   # build, install user LaunchAgent, start daemon, verify
./faraday               # open dashboard
./faraday check         # safe status/smoke-lite check
./faraday smoke         # restart smoke, no visual overlay
./faraday smoke --overlay  # explicit visual overlay test
./faraday stop          # unload daemon, keep install files
./faraday remove        # uninstall LaunchAgent/binaries, keep data
```

Default enforcement is dry-run. Faraday can lock macOS only after you explicitly switch to armed mode.

## Current status

Working MVP scaffold. Primary docs:

- [`docs/PRD.md`](docs/PRD.md) — software product requirements
- [`docs/PRODUCT.md`](docs/PRODUCT.md) — open-source and hardware product strategy
- [`docs/BEACONS.md`](docs/BEACONS.md) — beacon compatibility notes
- [`docs/LAUNCHD.md`](docs/LAUNCHD.md) — launchd install/restart/remove + smoke tests
- [`docs/MVP_VALIDATION.md`](docs/MVP_VALIDATION.md) — end-to-end manual validation harness and success-metric worksheet
- [`docs/BEACON_KIT_VIABILITY.md`](docs/BEACON_KIT_VIABILITY.md) — post-validation recommendation on third-party beacon kit strategy
- [`docs/adr/0001-launchd-weak-moment-resistance-posture.md`](docs/adr/0001-launchd-weak-moment-resistance-posture.md) — launch posture decision
- [`CONTEXT.md`](CONTEXT.md) — domain vocabulary

## Development principles

- Local-first: no cloud account or telemetry required for core use.
- Test core logic without BLE hardware.
- Mock enforcement in automated tests so tests never lock a developer Mac.
- Keep BLE scanning, RSSI classification, session state, enforcement, calibration, persistence, and launchd integration separate.

## Local dashboard (Bun TUI)

Run `./faraday` after setup. The dashboard connects over `~/.faraday/faraday.sock`, shows live status/event tail, and exposes setup, check, session, beacon scan/calibration, logs, stop, remove, and advanced commands.

Developer path without LaunchAgent:

- `swift run FaradayDaemon`
- `npm run tui`

## License

Apache-2.0. See [`LICENSE`](LICENSE).
