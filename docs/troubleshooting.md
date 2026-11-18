# Troubleshooting

Confirm the Proton CLI itself before assuming a widget bug. These failures belong to Proton, Arch packaging, or the local session:

```sh
pacman -Q proton-vpn-cli
protonvpn --help
protonvpn status
protonvpn countries list
```

The recorded parser fixtures target CLI versions 1.0.1 through 1.0.5. Versions outside that range receive a non-blocking compatibility warning; malformed status output still activates the existing stale-state safety gate.

**CLI not installed.** Choose **Install Proton VPN CLI** in the panel, or run `omarchy install app "Proton VPN CLI" proton-vpn-cli`. The bar tooltip reads “Proton VPN CLI not installed.”

**Sign-in required.** Choose **Sign in** in the panel, or run `protonvpn signin USERNAME` in a terminal. With a security key on CLI 1.0.5, add `--totp` to use an authenticator code instead.

**No internet after a drop.** If the panel says Kill Switch is blocking traffic, that is Kill Switch working. Connect again, or set Kill Switch to Off.

**Desktop app is running.** Quit the Proton VPN GUI. The CLI refuses to operate until it is closed.

**Keyring or Secret Service failure.** The CLI could not read saved credentials from the session keyring. Unlock or restart the keyring, then run `protonvpn status` in a terminal. The widget reports this as a local session error, not as signed-out and not as a parser bug.

**Daemon unavailable.** `proton-vpn-daemon` did not respond. Check the Proton CLI service, then refresh. This is a Proton CLI/service problem.

**Connection timeout.** `Timed out after 10s waiting for event(s): CONNECTED` means the CLI reached Proton but the handshake did not finish. Retry or check the network. This is separate from the widget's command-queue watchdog.

**"Nothing has come back through the tunnel."** The tunnel has sent data for 30 seconds without receiving any. The Proton server or the network under the VPN may be down. Reconnect, or switch servers. An idle tunnel never shows this, and the warning clears as soon as anything arrives.

**"IPv4 traffic leaves through …" or "IPv6 traffic leaves through …".** The kernel would send that traffic through the named device instead of the tunnel. A Tailscale exit node, another VPN, or a route you added can do this. Turn the other one off, or reconnect so Proton sets up its routes again. Proton's own Kill Switch and IPv6 leak protection devices never trigger it.

**"DNS goes to … outside the tunnel."** systemd-resolved sends ordinary lookups to that server on that device, so it sees the names you look up. Tailscale with "use Tailscale DNS" taking every name, or another link set to take every name, are the usual causes. Names only one network resolves, such as your tailnet's or your LAN's search domain, are not counted.

**"DNS goes to …, set system-wide."** A `DNS=` server in `resolved.conf` takes ordinary lookups: alongside the tunnel when it has `Domains=~.`, or instead of it when the tunnel does not claim them. Remove it, bind it to the tunnel (`DNS=10.2.0.1%proton0`), or reconnect so Proton sets its resolver again.

**Check says "check failed".** pacman's `checkupdates` could not reach your Arch mirrors; Check's tooltip has its message. Retry once the network is up. The versions shown stay as they were: from the local package database, or from an earlier Check that worked.

**Status looks outdated.** A failed or timed-out poll keeps the last good result and marks it stale. Connection and settings changes stay disabled until a fresh probe succeeds. Refresh after the network or Proton daemon recovers.

**Paid-plan or invalid option.** The panel shows the CLI message, or its own free-plan note, and keeps the previous healthy status when it can. Fastest connect remains available.

**Hung command.** A watchdog stops a stuck process and marks its job timed out. Queued commands start once that process has exited, and its late output is ignored.

**Update says it cannot fast-forward.** If you have not changed the checkout yourself, your copy predates a rewrite of this repository's history in September 2026. Remove the plugin and add it again; see [Uninstall](../README.md#uninstall) and [Install](../README.md#install).

## Limitations

- The official CLI cannot run at the same time as the Proton VPN desktop app. Close the GUI to use this widget.
- Headless setups and split tunneling are not supported by the CLI, so they are out of scope here.
- Location, feature, and some configuration choices can require a paid plan. The CLI does not report the plan, so the panel infers the free plan only from settings marked "Upgrade to enable". Until settings load, it shows the CLI's error instead.
- Reconnect on drop cannot tell a drop from a `protonvpn disconnect` typed in another terminal, so with it on, that disconnect is undone. Disconnect from the panel instead, or leave the setting off.
- `protonvpn status` does not provide the current exit IP. The widget never performs an external lookup, so the value is available only after a successful connect command that returned it.
- Omarchy creates a widget on each monitor. On Omarchy's built-in bar every panel uses one shared service, so Proton CLI commands are serialized across all monitors. Replacement bars cannot provide that service, so each panel there runs its own copy and polls separately.
- `protonvpn status` runs on a timer only while a panel is open. Each run starts Python and opens a new keyring connection, so with every panel closed it runs only at start-up, when the NetworkManager link changes, and after an action. If `nmcli` is unavailable, it keeps polling on the timer. The bar icon keeps following the tunnel through the read-only link probe, but a sign-out or a newly opened desktop app is noticed only when you open the panel or the link changes.
- The Proton CLI sometimes crashes while exiting, after printing its full output. Read-only commands (`status`, `countries list`, `cities list`, `config list`) accept that output when it parses. Settings must list every known key, and country or city lists from a crashed run are fetched again next time. Connect, disconnect, and setting changes never do.
- Desktop notifications are never sent while the panel is open.
- The tunnel check covers WireGuard tunnels on a `proton0`-style device, the CLI's default; the panel does not follow OpenVPN tunnels. It reads routes and resolver state, so it cannot see a block in the firewall: while Proton's opt-in firewall Kill Switch service runs, or the system bus cannot be read, IPv6 cannot be judged and shows no warning. DNS can be judged only when `/etc/resolv.conf` points at systemd-resolved's stub resolver (its `stub` or `static` mode). Tailscale and other changes NetworkManager does not report show within a minute.
- Changing Kill Switch while connected leaves you unprotected for a few seconds during the reconnect. That is why the panel asks first.
