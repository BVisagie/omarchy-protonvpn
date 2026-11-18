# Changelog

## 1.4.0 — 2026-11-17

- Rework the panel's layout. SETTINGS folds behind one row (`s`), so the panel opens on status and CONNECT. CONNECT puts Mode on its own row and the place on the row below, never more than two fields, with plain country and city names. A button under it names where it connects ("Connect to Santo Domingo · Dominican Republic", or "Switch to …" while connected). Refresh is an icon beside the switch, and status reads as one style, one line per topic. SETTINGS is borderless rows: NetShield, then the switches in two columns, then the CLI on one footer line; Kill Switch is a switch, captions live in tooltips, and labels are quiet so values stand out. The open panel fits without scrolling in all but its fullest states.
- Show the installed Proton VPN CLI version and the latest your package database knows. **Check** asks your Arch mirrors through `checkupdates`, only when you press it, and **Update** opens Omarchy's system update.
- Replace RECENT with **QUICK CONNECT**: the current connection, starred favorites, and recent places, by full name. A star, or `f`, keeps a place as a favorite in the widget's `shell.json` entry. A new `rememberRecent` setting also saves recent places there and starts CONNECT on the last one.
- Show how long you have been connected, what protects the connection (Kill Switch, NetShield, Secure Core), and protocols by their proper names.
- Warn in the panel, icon, and tooltip when the tunnel is up but nothing has come back through it for 30 seconds. It never reconnects on its own.
- Add `connectOnLogin`, which connects at the first shell start after login but not when the shell reloads, and `autoConnectWifi`, which connects on Wi-Fi networks you have not trusted. Both wait for Proton, try at most three times, and give way to anything you do.
- Add a `barLabel` setting to show the country, server, or city beside the bar icon.
- Sign out from SETTINGS while disconnected, after asking.
- Add IPC functions `connectFastest`, `connectTo`, `toggleVpn`, and `statusJson`.
- Follow Omarchy's language setting: every string goes through translation catalogs in `i18n/`, and numbers follow the language. English ships first. Requires Omarchy 4.5.
- Follow NetworkManager events through `nmcli monitor` instead of polling every 4 seconds, with a poll once a minute as a safety net. `linkWatchIntervalSec` now applies only while events are unavailable.
- Read traffic counters in place instead of starting `python3` and `cat` for every sample.
- Fix a successful command with no output reporting "Command failed".
- Refresh the README screenshots and the marketplace preview in Tokyo Night, Matte Black, and InkyPinky.
- Keep agent skill folders out of the plugin, validate the files a clone would contain, and add `scripts/load-smoke.sh`, which loads the widget in a throwaway Quickshell instance.

## 1.3.0 — 2026-10-05

- Show when Kill Switch is blocking internet traffic after a drop. The panel reads Proton's `pvpn-killswitch` connection from the existing `nmcli` probe, turns the bar icon urgent, and says how to restore access. Drop notifications say so too.
- Repeat the CLI's port-forwarding note after connecting, and explain that the forwarded port comes from Proton's `natpmpc` guide. The plugin still makes no network requests of its own.
- Test against Proton VPN CLI 1.0.5 and document its `--totp` sign-in option for accounts with a security key.
- Fix the bounded runner returning 143 when a command closed its output before exiting, and hanging until the deadline when a background process it left behind held the output open.
- Install the CLI and sign in from the panel. **Install Proton VPN CLI** opens Omarchy's installer, and **Sign in** opens a floating terminal that runs `protonvpn signin`. The panel checks back until either finishes.
- Send notifications through `omarchy-notification-send` with a shield glyph; clicking one opens the panel. Document the IPC functions for keybindings.
- Recognize the free plan from settings marked "Upgrade to enable", label paid-only modes, and explain them instead of running a command that fails. Kill Switch changes on the free plan now reconnect to the fastest server instead of a server ID the CLI refuses.
- Add an opt-in **Reconnect when the VPN drops** setting that retries with backoff and gives up with a notification.
- Take a per-user lock around Proton CLI runs, so two shells never run the CLI at the same time.

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
- Refresh the README and marketplace preview: new screenshots in three themes, a feature and requirements summary up front, menu install and removal steps, an Update section, and a widget settings table. Correct the install steps: adding the plugin asks whether to enable it, and enabling without `--section` uses the right section.

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
