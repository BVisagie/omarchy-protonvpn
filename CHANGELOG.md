# Changelog

## Unreleased

- Add a **Switch to …** button that reconnects in place when CONNECT choices change while connected.
- Enter in the Server ID field switches servers while connected instead of disconnecting.
- Run city lists, connection actions, and setting changes ahead of background refreshes.
- Cache city lists per country for the shell session and show "Loading cities…" on the City field.
- Stop forcing country and city reloads every time the panel opens.
- Re-check status after a failed switch instead of showing the old connection as still active.

## 1.1.0 — 2026-09-15

- Share one serialized Proton VPN service across all monitor widgets on the built-in bar, with a per-panel fallback on replacement bars.
- Bound subprocess output, enforce deadlines, and reap descendant processes.
- Add read-only NetworkManager tunnel observation for responsive bar state, without hiding desktop-app, sign-in, or CLI error states.
- Detect and report CLI compatibility for the tested 1.0.1–1.0.3 range.
- Show CLI-supplied exit IPs and three in-memory recent connection targets.
- Add a configurable live link check interval.
- Add portable manifest, parser, runner, and QML contract checks in CI.
- Document the expanded local command surface and unchanged privacy boundary.

## 1.0.0 — 2026-08-23

- Initial native Omarchy bar controls for the official Proton VPN Linux CLI.
