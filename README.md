# Proton VPN for Omarchy

Native Omarchy Quattro bar widget and keyboard-friendly panel for the official Proton VPN Linux CLI (`protonvpn`). NetworkManager is observed read-only so the bar reacts to tunnel changes without repeatedly starting the heavier CLI.

Every VPN action and setting change goes through the installed official CLI. The plugin does not reimplement Proton protocols, call Proton's private APIs, collect credentials, edit Proton files, or run unofficial VPN clients.

## Privacy

- The plugin executes a fixed set of local commands as argument arrays. It never interpolates values into a shell. See [Commands this plugin runs](#commands-this-plugin-runs).
- The runner caps stdout and stderr while commands execute, enforces deadlines, and reaps the complete child process group after a timeout or overflow.
- A read-only `nmcli connection show --active` probe observes `proton0`-style tunnel devices. It never creates, changes, or removes NetworkManager connections.
- It never collects, logs, stores, or passes Proton credentials.
- It never invokes `sudo` or `pkexec`.
- It never makes extra network requests such as “what is my IP” lookups, map tiles, or telemetry.
- The exit IP is shown only when the Proton CLI itself returns it after connecting. Exit IP and recent targets stay in memory and disappear when `omarchy-shell` exits. Captured test fixtures are synthetic or redacted.
- Raw CLI diagnostics are capped before they are shown.

Omarchy plugins run unsandboxed inside the long-lived `omarchy-shell` process with your user privileges. This plugin invokes `protonvpn` only after discovering it on `PATH`. Review the code before enabling it.

### Commands this plugin runs

Supervised by `scripts/run_bounded.py`, which caps output, enforces a deadline, and cleans up the process group:

- `/usr/bin/which protonvpn` to find the CLI
- `protonvpn` subcommands: `--help`, `status`, `connect`, `disconnect`, `countries list`, `cities list`, `config list`, and `config set`
- `/usr/bin/nmcli -t -e no -f NAME,TYPE,DEVICE,STATE connection show --active`

Started directly, only when you press the matching panel control:

- `wl-copy` copies the suggested install or sign-in command
- `omarchy-launch-terminal` opens a terminal for signing in

## Install

Omarchy’s **Add plugin** prompt asks only for the git URL. Paste this and nothing else:

```
https://github.com/BVisagie/omarchy-protonvpn.git
```

From a terminal, the same URL is the only required argument:

```sh
omarchy plugin add https://github.com/BVisagie/omarchy-protonvpn.git
```

That clones the plugin disabled so you can review it. Enable it when you are ready; right is the default section:

```sh
omarchy plugin enable io.github.BVisagie.protonvpn --section right
```

Omit `--section` to be asked **left**, **center**, or **right**. To move it later:

```sh
omarchy bar move io.github.BVisagie.protonvpn --section right
```

Requires NetworkManager, Python 3 at `/usr/bin/python3`, `which`, and `wl-clipboard`, all normally present on Omarchy. Without Python 3 no command can run. It also needs the official Proton VPN CLI on `PATH`:

```sh
sudo pacman -S proton-vpn-cli
```

The `proton-vpn-cli` package is available in Arch's `extra` repository. Arch is not one of Proton's officially supported Linux distributions, so upstream support and packaged updates may be limited. This plugin documents that limitation rather than claiming official Arch support.

After installing the CLI, sign in from a terminal. The panel never asks for a password or 2FA code:

```sh
protonvpn signin USERNAME
```

## Interaction

- **Left-click** the bar icon to open or close the panel.
- **Right-click** connects or disconnects only while status is healthy and idle. Otherwise it opens the panel.
- **Middle-click** refreshes when no Proton command is running.
- The bar icon uses theme colors: connected is full strength, disconnected is dimmed, and degraded states add a warning badge. A slash marks disconnected or signed-out. Tooltip text names the current state.

Inside the panel:

- `j` / `k` or up/down arrows move the cursor between rows
- `h` / `l` or left/right arrows move the cursor across a row
- `Enter` / `Space` activates the selected control
- `t` toggles connect/disconnect with the same safety gate as right-click
- `r` refreshes
- `Tab` / `Shift+Tab` switches to the next bar panel
- `Esc` closes

Up to three successful connection targets appear under **RECENT** for the current shell session. They are never written to disk. When the CLI supplies a new exit IP after connecting, the panel shows it until the tunnel disconnects or changes.

Connection modes match the current CLI: fastest, country, city, specific server ID, Secure Core, P2P, Tor, and random. Country and city lists come from `protonvpn countries list` and `protonvpn cities list`. Server IDs are entered as text because the CLI does not expose a machine-readable server list; Proton publishes IDs at [the account WireGuard server list](https://account.proton.me/vpn/WireGuard).

Settings cover every value exposed by `protonvpn config` on the tested CLI 1.0.1–1.0.3 range: NetShield, Kill Switch, port forwarding, custom DNS, VPN Accelerator, moderate NAT, IPv6, and anonymous crash reports. Kill Switch changes require disconnecting first. IPv6 and custom DNS need a new VPN connection to apply. Custom DNS is validated locally and passed as one `--dns` argument.

Some rows show a short caption. Hover a CONNECT or SETTINGS control, or move onto it with `j` / `k`, for a Proton-sourced tooltip. That copy is paraphrased from Proton’s official support articles and the Linux CLI guide. It is not a substitute for those pages, and the widget does not fetch Proton’s website.

## Limitations

- The official CLI cannot run at the same time as the Proton VPN desktop app. Close the GUI to use this widget.
- Headless setups and split tunneling are not supported by the CLI, so they are out of scope here.
- Location, feature, and some configuration choices can require a paid plan. The panel shows the CLI's error instead of guessing the account tier.
- `protonvpn status` does not provide the current exit IP. The widget never performs an external lookup, so the value is available only after a successful connect command that returned it.
- Omarchy creates a widget on each monitor. On Omarchy's built-in bar every panel uses one shared service, so Proton CLI commands are serialized across all monitors. Replacement bars cannot provide that service, so each panel there runs its own copy and polls separately.
- Status polling defaults to 30 seconds because `protonvpn status` initializes Proton components and may refresh server data while connected. It can be changed in widget settings (10–3600 seconds).
- The live link probe defaults to four seconds and can be changed in widget settings. If `nmcli` is unavailable, normal CLI polling continues.

## Troubleshooting

Confirm the Proton CLI itself before assuming a widget bug. These failures belong to Proton, Arch packaging, or the local session:

```sh
pacman -Q proton-vpn-cli
protonvpn --help
protonvpn status
protonvpn countries list
```

The recorded parser fixtures target CLI versions 1.0.1 through 1.0.3. Versions outside that range receive a non-blocking compatibility warning; malformed status output still activates the existing stale-state safety gate.

**CLI not installed.** Install `proton-vpn-cli` from Arch extra, then refresh. The bar tooltip reads “Proton VPN CLI not installed.”

**Sign-in required.** Run `protonvpn signin USERNAME` in a terminal. Copy the command from the panel if useful. Refresh after signing in.

**Desktop app is running.** Quit the Proton VPN GUI. The CLI refuses to operate until it is closed.

**Keyring or Secret Service failure.** The CLI could not read saved credentials from the session keyring. Unlock or restart the keyring, then run `protonvpn status` in a terminal. The widget reports this as a local session error, not as signed-out and not as a parser bug.

**Daemon unavailable.** `proton-vpn-daemon` did not respond. Check the Proton CLI service, then refresh. This is a Proton CLI/service problem.

**Connection timeout.** `Timed out after 10s waiting for event(s): CONNECTED` means the CLI reached Proton but the handshake did not finish. Retry or check the network. This is separate from the widget's command-queue watchdog.

**Status looks outdated.** A failed or timed-out poll keeps the last good result and marks it stale. Connection and settings changes stay disabled until a fresh probe succeeds. Refresh after the network or Proton daemon recovers.

**Paid-plan or invalid option.** The panel shows the CLI message and keeps the previous healthy status when it can. Fastest connect remains available.

**Hung command.** A watchdog stops a stuck process and marks its job timed out. Queued commands start once that process has exited, and its late output is ignored.

**Validate the plugin:**

```sh
./scripts/check.sh
```

That script runs Node and Python tests, `omarchy plugin validate .` when Omarchy is installed, a QML contract check, bounded-runner tests, a `qmllint` syntax check, and shell-load smoke tests. The same portable checks run in GitHub Actions. `qmllint` reports many unresolved-import warnings because Quickshell and Omarchy imports only resolve inside `omarchy-shell`. The script ignores those and fails only on syntax errors, so a pass does not prove the widget loads. Test it in the bar before releasing.

## Architecture

- `Service.qml` is the Omarchy service shared by every monitor. Its scheduler serializes all Proton CLI work.
- `Panel.qml` contains the compact bar control and reads state from the shared service. When the bar cannot provide one, it runs a local `Service` instance instead.
- `Model.js` contains parsers, validation, compatibility detection, and display rules covered by captured fixtures.
- `scripts/run_bounded.py` is a local process supervisor; it does not implement VPN behavior or make network requests.

## Credits

The shared-service, live-link, and process-hardening work was informed by the community plugins [iamfitsum/omarchy-proton-vpn](https://github.com/iamfitsum/omarchy-proton-vpn) and [glorics/omarchy-proton-vpn](https://github.com/glorics/omarchy-proton-vpn). Their broader private-API, keyring, settings-file, online-map, and external-IP behavior is intentionally not included here.

## Uninstall

```sh
omarchy plugin remove io.github.BVisagie.protonvpn
```

This removes the plugin from Omarchy. It does not uninstall `proton-vpn-cli` or sign out of Proton VPN.

## License

MIT. See [LICENSE](LICENSE).

Release history is recorded in [CHANGELOG.md](CHANGELOG.md).
