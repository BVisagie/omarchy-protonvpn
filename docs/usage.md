# Using the panel

- **Left-click** the bar icon to open or close the panel.
- **Right-click** connects or disconnects only while status is healthy and idle. Otherwise it opens the panel.
- **Middle-click** refreshes when no Proton command is running.
- The bar icon uses theme colors: connected is full strength, disconnected is dimmed, and degraded states add a warning badge. A slash marks disconnected or signed-out. Tooltip text names the current state.
- The line at the foot of the panel names the plugin version and, in a git install, the commit it runs from, with ", modified" after local edits. Quote it in bug reports.

Inside the panel:

- `j` / `k` or up/down arrows move the cursor between rows
- `h` / `l` or left/right arrows move the cursor across a row
- `Enter` / `Space` activates the selected control
- `t` toggles connect/disconnect with the same safety gate as right-click
- `f` stars or unstars the QUICK CONNECT row under the cursor
- `s` shows or hides SETTINGS, which starts folded so the panel opens on status and CONNECT
- `r` refreshes
- `Tab` / `Shift+Tab` switches to the next bar panel
- `Esc` hides a tooltip that is showing, then closes the panel; in the Server ID or DNS field it first hands the keys back to the panel

CONNECT has Mode on its own row and the place, Country and City or a Server ID, on the row below. While disconnected, a button under them names where it connects (**Connect to Santo Domingo · Dominican Republic**). While connected, changing the choices turns it into **Switch to …**, which reconnects in place with the new choices; `Enter` in the Server ID field does the same. The header toggle and `t` still disconnect. City lists are cached for the shell session, so picking a country again shows its cities immediately; the refresh icon beside the toggle reloads them, and its tooltip says when status was last updated.

**QUICK CONNECT** lists, by full name ("Zurich · Switzerland"), the current connection, your favorites, and the last three places you connected to. Click a row, or press `Enter` on it, to connect there. Click its star, or press `f` on the row, to keep it as a favorite or remove it. Favorites, up to eight, are saved in this widget's entry in `~/.config/omarchy/shell.json`. Recent places stay in memory for the shell session unless you turn on `rememberRecent`, which also saves them there and starts CONNECT on the last one; turning it off removes them again. When the CLI supplies a new exit IP after connecting, the panel shows it until the tunnel disconnects or changes.

Country and city lists come from `protonvpn countries list` and `protonvpn cities list`. Server IDs are entered as text because the CLI does not expose a machine-readable server list; Proton publishes IDs at [the account WireGuard server list](https://account.proton.me/vpn/WireGuard).

SETTINGS shows NetShield on its own row, the switches in two columns, and the CLI on a footer line. Settings cover every value exposed by `protonvpn config` on the tested CLI 1.0.1–1.0.5 range: NetShield, Kill Switch, port forwarding, custom DNS, VPN Accelerator, moderate NAT, IPv6, and anonymous crash reports. Changing Kill Switch while connected asks first, with Cancel selected. Confirming disconnects, changes the setting, and reconnects to the same target. If Proton rejects the change, the panel still reconnects and shows the error. IPv6 and custom DNS need a new VPN connection to apply. Custom DNS is validated locally and passed as one `--dns` argument.

With Kill Switch on, a drop leaves internet traffic blocked until the VPN reconnects. The panel reads that from NetworkManager's active connections: the bar icon turns urgent and the panel says traffic is blocked, so you know to connect again or turn Kill Switch off.

With port forwarding on, the panel repeats what the CLI says after connecting: whether the server supports it. The CLI does not show the forwarded port. Proton's [Linux port-forwarding guide](https://protonvpn.com/support/port-forwarding-manual-setup) reads it with `natpmpc`, and this plugin does not run that for you, because it would be a network request of its own.

On Proton's free plan the CLI only connects to the fastest server. When `protonvpn config list` marks settings "Upgrade to enable", the panel labels the other modes as needing a paid plan and explains that instead of running a command that would fail. A Kill Switch change or an automatic reconnect then returns to the fastest server.

While disconnected, the footer line of SETTINGS offers **Sign out**. Pressing it turns the line into a confirm, with Cancel selected; confirming runs `protonvpn signout`, which also clears the CLI's own settings. Favorites stay. Disconnect first if you are connected.

The same footer line shows the installed Proton VPN CLI version, and the newer one when your package database knows it, or "Up to date" once it knows the latest; **Check**'s tooltip says how old that database is. It reads that locally. **Check** asks your Arch mirrors instead, through pacman's `checkupdates`, only when you press it. When a newer version exists, **Update** opens Omarchy's own system update in a terminal, which asks for your password there; Arch does not support updating one package alone, so the CLI updates with everything else.

Hover a CONNECT or SETTINGS control, or move onto it with `j` / `k`, for a Proton-sourced tooltip. A setting's tooltip also says when it needs a new connection or a paid plan. That copy is paraphrased from Proton’s official support articles and the Linux CLI guide. It is not a substitute for those pages, and the widget does not fetch Proton’s website.

## Languages

The panel follows **Setup → Language** live, without a shell restart. Its strings live in `i18n/`, one JSON catalog per Omarchy language code. Only English ships today; a missing string falls back to English. To add a language, copy `i18n/en.json` to the language's code (for example `i18n/de.json`) and translate the values, keeping each `%1` placeholder. Proton CLI output, server names, and diagnostics stay as the CLI wrote them.

After changing a string in the code, run `node tests/tools/build_catalog.js` to rewrite `i18n/en.json`; the tests fail until it matches.

## Widget settings

| Setting | Key | Default | Range or values |
|---|---|---|---|
| Status refresh while the panel is open | `refreshIntervalSec` | 30 seconds | 10–3600 |
| Link check interval when NetworkManager events are unavailable | `linkWatchIntervalSec` | 4 seconds | 2–60 |
| Desktop notifications (only while the panel is closed) | `notifications` | `drops` | `off`, `drops`, `all` |
| Reconnect when the VPN drops | `reconnectOnDrop` | `false` | `true`, `false` |
| Remember recent connections and the last target across restarts | `rememberRecent` | `false` | `true`, `false` |
| Connect when you log in | `connectOnLogin` | `false` | `true`, `false` |
| Connect on Wi-Fi networks you have not trusted | `autoConnectWifi` | `false` | `true`, `false` |
| Text beside the bar icon while connected | `barLabel` | `none` | `none`, `country` (NL), `server` (NL#806), `city` (Amsterdam) |

Change a setting with `omarchy bar set`. Numbers and booleans need `--json`:

```sh
omarchy bar set io.github.BVisagie.protonvpn notifications all
omarchy bar set io.github.BVisagie.protonvpn refreshIntervalSec 60 --json
omarchy bar set io.github.BVisagie.protonvpn reconnectOnDrop true --json
omarchy bar set io.github.BVisagie.protonvpn barLabel country
```

The bar label shows only while connected, and only on horizontal bars.

With `connectOnLogin` on, the first shell start after you log in connects to the fastest server, or to your last place with `rememberRecent` on. It does not connect when the shell merely reloads, for example after a theme change: the plugin's lock file for the current Hyprland session tells the two apart. It waits for Proton to report Disconnected, checking every 10 seconds for up to 3 minutes while the network and Proton's services come up, and tries at most 3 times. Connecting or disconnecting yourself in that time cancels it, and it never runs while you are signed out. With Kill Switch on, a network that needs a sign-in page (a captive portal) may not let it through until you disconnect.

With `autoConnectWifi` on, joining a Wi-Fi network you have not trusted connects the same way, once per join, with the same waiting, limits, and cancelling. SETTINGS then shows **Trust** for the current network, which skips it from then on, or **Stop trusting**. Trusted names are saved as `trustedNetworks` in this widget's entry in `~/.config/omarchy/shell.json`. The plugin reads the current network from NetworkManager over D-Bus, through Quickshell, without starting a process. It never disconnects on a trusted network, a shell reload never counts as joining one, and a network whose name NetworkManager does not report counts as trusted. Sign in to a captive portal before you join it with Kill Switch on, or trust it.

A drop is any tunnel loss the widget did not start itself, including one from another terminal. `drops` and `all` also notify when the tunnel check first finds traffic or DNS outside the tunnel, and `all` notifies when the tunnel connects. Notifications go through `omarchy-notification-send`; clicking one opens the panel.

With `reconnectOnDrop` on, a drop starts a reconnect to the same target after 3 seconds, then retries after 10 seconds, 30 seconds, 1 minute, and 2 minutes before giving up with a notification. Connecting or disconnecting from the panel cancels it. The widget follows drops through `nmcli`, so this needs NetworkManager's link probe to work.

## Keybindings

The panel answers Omarchy shell IPC on the target `io.github.BVisagie.protonvpn`:

| Function | What it does |
|---|---|
| `open`, `close`, `toggle` | Show or hide the panel |
| `refresh` | Re-read status, locations, and settings |
| `connectVpn` | Connect with the panel's current CONNECT choices |
| `connectFastest` | Connect to the fastest server |
| `connectTo <place>` | Connect to `NL`, `CH#242`, `US New York`, `p2p`, `securecore`, or `tor` with an optional country code (`p2p NL`), or `random` or `fastest` |
| `disconnectVpn` | Disconnect |
| `toggleVpn` | Connect or disconnect, like right-click |
| `status` | The tooltip text |
| `statusJson` | State, server, location, load, protocol, exit IP, connection start, Kill Switch, NetShield, warnings, and the tunnel check as JSON: `routing` gives the latest reading of `ipv4`, `ipv6`, and `dns` as `ok`, `blocked`, `none`, `leak`, or `unknown`, and `leaks` lists only the confirmed leaks |

The connect and disconnect functions do nothing while a command is running or status is not healthy; `connectFastest` and `connectTo` print why. For example, in `~/.config/hypr/bindings.conf`, using keys that are free in your setup:

```
bindd = SUPER ALT, V, Proton VPN panel, exec, omarchy-shell io.github.BVisagie.protonvpn toggle
bindd = SUPER ALT SHIFT, V, Proton VPN connect, exec, omarchy-shell io.github.BVisagie.protonvpn connectVpn
bindd = SUPER ALT CTRL, V, Proton VPN to Switzerland, exec, omarchy-shell io.github.BVisagie.protonvpn connectTo CH
```

`statusJson` suits scripts and status lines:

```sh
omarchy-shell io.github.BVisagie.protonvpn statusJson | jq -r .server
```
