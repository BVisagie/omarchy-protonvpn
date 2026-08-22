# Proton VPN for Omarchy

Native Omarchy Quattro bar widget and keyboard-friendly panel for the official Proton VPN Linux CLI (`protonvpn`).

This plugin talks only to the installed CLI. It does not reimplement Proton protocols, call Proton's private APIs, collect credentials, or run unofficial VPN wrappers.

## Install

The widget is a third-party Omarchy plugin. Plugins run unsandboxed inside the long-lived `omarchy-shell` process with your user privileges. Review the code before enabling it.

```sh
omarchy plugin add https://github.com/BVisagie/omarchy-protonvpn.git --enable
omarchy bar move io.github.BVisagie.protonvpn --section right
```

Requires the official Proton VPN CLI on `PATH`:

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

- `j` / `k` or arrows move the cursor
- `Enter` / `Space` activates the selected control
- `t` toggles connect/disconnect with the same safety gate as right-click
- `r` refreshes
- `Tab` / `Shift+Tab` switches to the next bar panel
- `Esc` closes

Connection modes match the current CLI: fastest, country, city, specific server ID, Secure Core, P2P, Tor, and random. Country and city lists come from `protonvpn countries list` and `protonvpn cities list`. Server IDs are entered as text because the CLI does not expose a machine-readable server list; Proton publishes IDs at [the account WireGuard server list](https://account.proton.me/vpn/WireGuard).

Settings cover every value exposed by `protonvpn config` on CLI 1.0.1: NetShield, kill switch, port forwarding, custom DNS, VPN Accelerator, moderate NAT, IPv6, and anonymous crash reports. Kill switch changes require disconnecting first. IPv6 and custom DNS need a new VPN connection to apply. Custom DNS is validated locally and passed as one `--dns` argument.

## Privacy

- The plugin executes only fixed official CLI commands as argument arrays. It never interpolates values into a shell.
- It never collects, logs, stores, or passes Proton credentials.
- It never invokes `sudo` or `pkexec`.
- It never makes extra network requests such as “what is my IP” lookups or telemetry.
- Connection details stay in memory. Captured test fixtures are redacted.
- Raw CLI diagnostics are capped before they are shown.

Omarchy plugins run with the user's privileges. This plugin invokes `protonvpn` only after discovering it on `PATH`.

## Limitations

- The official CLI cannot run at the same time as the Proton VPN desktop app. Close the GUI to use this widget.
- Headless setups and split tunneling are not supported by the CLI, so they are out of scope here.
- Location, feature, and some configuration choices can require a paid plan. The panel shows the CLI's error instead of guessing the account tier.
- `protonvpn status` does not provide the current exit IP; the widget does not add another lookup to display one.
- One widget instance is created per monitor. Commands are serialized per instance. Shared singleton polling can be added later if duplicate polls become a problem.
- Status polling defaults to 30 seconds because `protonvpn status` initializes Proton components and may refresh server data while connected.

## Troubleshooting

**CLI not installed.** Install `proton-vpn-cli` from Arch extra, then refresh. The bar tooltip reads “Proton VPN CLI not installed.”

**Sign-in required.** Run `protonvpn signin USERNAME` in a terminal. Copy the command from the panel if useful. Refresh after signing in.

**Desktop app is running.** Quit the Proton VPN GUI. The CLI refuses to operate until it is closed.

**Status looks outdated.** A failed or timed-out poll keeps the last good result and marks it stale. Refresh after the network or Proton daemon recovers.

**Paid-plan or invalid option.** The panel shows the CLI message and keeps the previous healthy status when it can. Fastest connect remains available.

**Hung command.** A watchdog stops a stuck process so later refreshes can run.

**Validate the plugin:**

```sh
omarchy plugin validate .
node --test tests/model.test.js
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml ProtonVpnIcon.qml
```

Recorded parser fixtures target `proton-vpn-cli` 1.0.1-1. When a newer CLI changes output, update the fixtures and parser together.

## Uninstall

```sh
omarchy plugin remove io.github.BVisagie.protonvpn
```

This removes the plugin from Omarchy. It does not uninstall `proton-vpn-cli` or sign out of Proton VPN.

## License

MIT. See [LICENSE](LICENSE).
