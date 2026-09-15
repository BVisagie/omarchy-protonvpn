# Changelog

## 1.1.0 — 2026-09-15

- Share one serialized Proton VPN service across all monitor widgets.
- Bound subprocess output, enforce deadlines, and reap descendant processes.
- Add read-only NetworkManager tunnel observation for responsive bar state.
- Detect and report CLI compatibility for the tested 1.0.1–1.0.3 range.
- Show CLI-supplied exit IPs and three in-memory recent connection targets.
- Add portable manifest, parser, runner, and QML contract checks in CI.
- Document the expanded local command surface and unchanged privacy boundary.
- Fall back to a panel-local service on bars that cannot provide the shared one.
- Keep desktop-app conflict, sign-in, and error states visible while a tunnel is up.
- Stop trusting a remembered tunnel over CLI "Disconnected" when nmcli fails.
- Resume queued commands after a timed-out command finally exits.

## 1.0.0 — 2026-08-23

- Initial native Omarchy bar controls for the official Proton VPN Linux CLI.
