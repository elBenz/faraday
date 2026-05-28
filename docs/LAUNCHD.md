# Launchd Operations (MVP posture)

This document defines Faraday's MVP launchd posture and manual operations.

Decision source: `docs/adr/0001-launchd-weak-moment-resistance-posture.md`.

## Posture summary

- Default mode: **user LaunchAgent**
- Optional serious mode: **root-owned LaunchDaemon**
- Both modes: `KeepAlive` enabled for crash restart
- Security expectation: weak-moment resistance, not local-admin-proof security

## Plist labels

- LaunchAgent label: `works.earendil.faraday.agent`
- LaunchDaemon label: `works.earendil.faraday.daemon`

> Replace paths/labels below with final implementation values when installer lands.

## User-facing command surface

The MVP user-facing command surface is intentionally small:

```bash
./faraday          # open dashboard; auto-starts installed LaunchAgent if needed
./faraday setup    # build, install, start, and verify user LaunchAgent
./faraday check    # status, doctor output, and smoke-lite verification
./faraday stop     # unload/disable daemon temporarily; keep installation files
./faraday remove   # unload and remove LaunchAgent plist; verify no relaunch
```

Advanced commands may exist for development (`start`, `restart`, `status`, `smoke`, `doctor`) but should not be the primary documented product surface. `smoke` must not show a blocking overlay by default; visual overlay smoke requires `./faraday smoke --overlay` and must clean up the session/overlay afterward.

`setup` must be idempotent and safe to rerun. It always runs `swift build`, copies `FaradayDaemon` and `FaradayOverlayHelper` into `~/.faraday/bin/`, and points launchd at that stable install path. Before enabling the LaunchAgent, it must explain that Faraday starts at login, restarts if it exits, can show overlays, and can lock macOS only in explicit armed mode. It must also show how to stop temporarily and remove completely.

`stop` means the daemon stays stopped until the user runs `setup` or an explicit start command. It should unload/disable the LaunchAgent job while leaving installation files in place.

## Install / restart / remove

### A) User LaunchAgent (default MVP)

Install (via dashboard control):

```text
launchagent install
```

Status/stop/restart/remove (via dashboard controls or `./faraday` command):

```text
./faraday check
./faraday stop
./faraday restart
./faraday remove
```

Install (manual fallback):

```bash
mkdir -p ~/Library/LaunchAgents
cp ./dist/works.earendil.faraday.agent.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/works.earendil.faraday.agent.plist
launchctl enable gui/$(id -u)/works.earendil.faraday.agent
launchctl kickstart -k gui/$(id -u)/works.earendil.faraday.agent
```

Restart:

```bash
launchctl kickstart -k gui/$(id -u)/works.earendil.faraday.agent
```

Remove:

```bash
launchctl bootout gui/$(id -u)/works.earendil.faraday.agent || true
rm -f ~/Library/LaunchAgents/works.earendil.faraday.agent.plist
```

### B) Root LaunchDaemon (optional serious mode)

Install:

```bash
sudo cp ./dist/works.earendil.faraday.daemon.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/works.earendil.faraday.daemon.plist
sudo chmod 644 /Library/LaunchDaemons/works.earendil.faraday.daemon.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/works.earendil.faraday.daemon.plist
sudo launchctl enable system/works.earendil.faraday.daemon
sudo launchctl kickstart -k system/works.earendil.faraday.daemon
```

Restart:

```bash
sudo launchctl kickstart -k system/works.earendil.faraday.daemon
```

Remove:

```bash
sudo launchctl bootout system/works.earendil.faraday.daemon || true
sudo rm -f /Library/LaunchDaemons/works.earendil.faraday.daemon.plist
```

## KeepAlive expectations

Plists should set:

- `RunAtLoad = true`
- `KeepAlive = true`

Operational expectation:

- Process starts automatically at login/boot (mode-dependent).
- Process auto-restarts after crash/exit.

## Manual smoke tests

Run these before calling launchd integration done.

1. **Startup behavior**
   - Install selected mode.
   - Reboot (daemon mode) or log out/in (agent mode).
   - Verify process/job is present via `launchctl print ...` and app status endpoint/log.

2. **Crash restart behavior**
   - Kill Faraday process (`kill -9 <pid>`).
   - Confirm launchd restarts it within a short interval.

3. **Remove behavior**
   - Run remove steps.
   - Verify job is absent and does not relaunch.

4. **Weak-moment posture check**
   - Confirm docs/user messaging explicitly state local-admin limits.
   - Confirm serious mode requires admin action to unload/remove.
