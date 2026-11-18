# Security

Omarchy plugins run unsandboxed inside the long-lived `omarchy-shell` process with the user's privileges. Review this repository before enabling it.

This plugin:

- sends VPN actions and configuration changes only to the official `protonvpn` CLI;
- runs only the fixed commands listed under [Commands this plugin runs](docs/privacy.md#commands-this-plugin-runs);
- passes commands as argument arrays without shell interpolation; the one script it hands to a terminal, for sign-in, is a fixed string with no plugin values in it;
- supervises every command whose output it reads with output limits, deadlines, process-group cleanup, and, for `protonvpn`, a per-user lock, except `nmcli monitor`, a long-running stream whose lines are read one at a time and discarded (`wl-copy`, `omarchy-install-app`, Omarchy's update terminal, and the sign-in terminal start directly, only when you use the matching control, and `omarchy-notification-send` starts directly with fixed text when the tunnel changes, or the tunnel check finds a leak, while the panel is closed);
- reads tunnel byte counters from `/sys/class/net/<device>/statistics` only for a validated `proton0`-style device and only while that tunnel is up, in place and without starting a process;
- reads the plugin's own commit once when it loads, with `git describe` on its checkout, for the version line;
- uses `nmcli` only to read active connection metadata and to follow NetworkManager's change events (`nmcli monitor`);
- while connected, reads routes with `ip route get` (a lookup that sends nothing), systemd-resolved's state with `resolvectl status`, and, only when IPv6 seems to leave outside the tunnel, the system bus's service list with `busctl list`;
- never asks for or stores Proton credentials; the sign-in terminal passes only the username, and the CLI asks for the rest;
- never runs anything as root; installing or updating the CLI goes through Omarchy's installer or system update, each of which asks for the password in its own terminal;
- never calls private Proton APIs, external IP services, telemetry, or map services, and reaches the network itself only through pacman's `checkupdates` when you press **Check** in SETTINGS;
- never edits Proton, NetworkManager, keyring, or system configuration files, and writes to Omarchy's `shell.json` only its own widget entry, through Omarchy's plugin API, to save favorites, trusted Wi-Fi names, and, when `rememberRecent` is on, recent connection choices;
- follows the current Wi-Fi network name from NetworkManager through Quickshell, in memory, and acts on it only when `autoConnectWifi` is on; and
- keeps CLI-supplied exit IPs and traffic totals in memory only, and recent connection targets too unless `rememberRecent` is on.

Parser failures and failed status probes retain the last known state as stale and disable VPN or configuration writes until a healthy probe succeeds.

Please use GitHub's private vulnerability reporting when it is available, or contact the repository owner privately before public disclosure. Include the plugin version line from the foot of the panel ("Plugin 1.6.0 · e991c06"), Omarchy version, Proton CLI package version, and a minimal reproduction with credentials and IP addresses removed.
