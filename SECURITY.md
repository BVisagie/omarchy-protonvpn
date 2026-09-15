# Security

Omarchy plugins run unsandboxed inside the long-lived `omarchy-shell` process with the user's privileges. Review this repository before enabling it.

This plugin:

- sends VPN actions and configuration changes only to the official `protonvpn` CLI;
- runs only the fixed commands listed under [Commands this plugin runs](README.md#commands-this-plugin-runs);
- passes commands as argument arrays without shell interpolation;
- supervises every command whose output it reads with output limits, deadlines, and process-group cleanup (`wl-copy` and `omarchy-launch-terminal` start directly, only when you use the matching control);
- uses `nmcli` only to read active connection metadata;
- never asks for or stores Proton credentials;
- never invokes `sudo` or `pkexec`;
- never calls private Proton APIs, external IP services, telemetry, or map services;
- never edits Proton, NetworkManager, keyring, Omarchy, or system configuration files; and
- keeps CLI-supplied exit IPs and recent connection targets in memory only.

Parser failures and failed status probes retain the last known state as stale and disable VPN or configuration writes until a healthy probe succeeds.

Please use GitHub's private vulnerability reporting when it is available, or contact the repository owner privately before public disclosure. Include the affected plugin version, Omarchy version, Proton CLI package version, and a minimal reproduction with credentials and IP addresses removed.
