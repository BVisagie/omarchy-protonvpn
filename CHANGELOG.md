# Changelog

## Unreleased

- Refresh the README and marketplace preview for 1.2.0: new screenshots in three themes, a feature and requirements summary up front, menu install and removal steps, an Update section, and a widget settings table. Correct the install steps: adding the plugin asks whether to enable it, and enabling without `--section` uses the right section.

## 1.2.0 — 2026-09-18

- Send a desktop notification when the tunnel drops unexpectedly while the panel is closed. A new **Desktop notifications** setting offers Off, drops only (default), or drops and connections.
- Change Kill Switch while connected: the panel asks first, then disconnects, applies the change, and reconnects to the same target, still reconnecting if Proton rejects the change.
- Show live download and upload rates and session totals from the tunnel's kernel counters, sampled only while the panel is open.
- Run `protonvpn status` on a timer only while a panel is open. With every panel closed, status runs only on start-up, link changes, and actions, so Proton no longer opens a keyring connection every 30 seconds around the clock.
- Accept complete `status`, country, city, and settings output when the Proton CLI crashes while exiting, instead of marking the status stale. Settings must list every known key, crashed country and city lists are fetched again next time, and writes still require a clean exit.
- Keep polling status on the timer while `nmcli` is unavailable, even with the panel closed.
- Report signal-killed commands as 128 + signal from the bounded runner.
- Add a **Switch to …** button that reconnects in place when CONNECT choices change while connected.
- Enter in the Server ID field switches servers while connected instead of disconnecting.
- Run city lists, connection actions, and setting changes ahead of background refreshes.
- Cache city lists per country for the shell session and show "Loading cities…" on the City field.
- Stop forcing country and city reloads every time the panel opens.
- Re-check status after a failed switch instead of showing the old connection as still active.
- Leave the current connection out of RECENT, so it lists only places you can switch to.
- Center the protocol pill with the power toggle and keep status details on one line beside Refresh.

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
