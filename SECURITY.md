# Security

Omarchy plugins run unsandboxed inside the long-lived `omarchy-shell` process with the user's privileges. Review this repository before enabling it.

This plugin:

- sends VPN actions and configuration changes only to the official `protonvpn` CLI;
- runs only the fixed commands listed under [Commands this plugin runs](README.md#commands-this-plugin-runs);
- passes commands as argument arrays without shell interpolation; the one script it hands to a terminal, for sign-in, is a fixed string with no plugin values in it;
- supervises every command whose output it reads with output limits, deadlines, process-group cleanup, and, for `protonvpn`, a per-user lock (`wl-copy`, `omarchy-install-app`, and the sign-in terminal start directly, only when you use the matching control, and `omarchy-notification-send` starts directly with fixed text when the tunnel changes while the panel is closed);
- reads tunnel byte counters from `/sys/class/net/<device>/statistics` only for a validated `proton0`-style device and only while the panel is open;
- uses `nmcli` only to read active connection metadata;
- never asks for or stores Proton credentials; the sign-in terminal passes only the username, and the CLI asks for the rest;
- never runs anything as root; installing the CLI goes through Omarchy's installer, which asks for the password in its own terminal;
- never calls private Proton APIs, external IP services, telemetry, or map services;
- never edits Proton, NetworkManager, keyring, Omarchy, or system configuration files; and
- keeps CLI-supplied exit IPs, recent connection targets, and traffic totals in memory only.

Parser failures and failed status probes retain the last known state as stale and disable VPN or configuration writes until a healthy probe succeeds.

Please use GitHub's private vulnerability reporting when it is available, or contact the repository owner privately before public disclosure. Include the affected plugin version, Omarchy version, Proton CLI package version, and a minimal reproduction with credentials and IP addresses removed.
