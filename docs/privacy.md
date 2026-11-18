# Privacy

- The plugin executes a fixed set of local commands as argument arrays. It never interpolates values into a shell. See [Commands this plugin runs](#commands-this-plugin-runs).
- The runner caps stdout and stderr while commands execute, enforces deadlines, and reaps the complete child process group after a timeout or overflow, or when a background process the command left behind still holds its output.
- Proton CLI runs take a lock in your runtime directory (`$XDG_RUNTIME_DIR/omarchy-protonvpn-<Hyprland session>.lock`, or `omarchy-protonvpn.lock` outside Hyprland), so two shells never run the CLI at the same time. The lock file is empty, and a new one per login also tells the widget a login from a shell reload.
- A read-only `nmcli monitor` stream says when NetworkManager changes anything, and a read-only `nmcli connection show --active` probe then reads the `proton0`-style tunnel. With the stream running, the probe otherwise runs once a minute; without it, every `linkWatchIntervalSec`. Neither creates, changes, or removes NetworkManager connections.
- It never collects, logs, stores, or passes Proton credentials. The sign-in terminal passes only your username to the CLI.
- It never runs anything as root. Installing or updating the CLI goes through Omarchy's installer or system update, each of which asks for your password in its own terminal.
- It never makes extra network requests such as “what is my IP” lookups, map tiles, or telemetry. The one exception is **Check** in SETTINGS, which runs pacman's `checkupdates` against your Arch mirrors only when you press it.
- The exit IP is shown only when the Proton CLI itself returns it after connecting. Exit IP and traffic totals stay in memory and disappear when `omarchy-shell` exits.
- Quickshell keeps the name of the Wi-Fi network you are on in memory, from NetworkManager. The plugin acts on it only with `autoConnectWifi` on, and saves the names you trust in its `shell.json` entry.
- Favorites, and recent places only with `rememberRecent` on, are saved as connection choices (mode, country code, city, server ID) in this widget's own entry in `~/.config/omarchy/shell.json`, through Omarchy's plugin API. If you keep your dotfiles in a public repository, that file shows where you connect.
- While connected, the tunnel check asks the kernel which device would carry traffic to 1.1.1.1 and 2606:4700:4700::1111 (`ip route get` looks the route up and sends nothing) and asks systemd-resolved where it sends lookups (`resolvectl status`). It runs when NetworkManager reports a change, at least once a minute, and when a panel opens. Its findings stay in memory.
- Traffic rates come from the tunnel's own kernel counters under `/sys/class/net/`. While the tunnel is up they are read every two seconds with the panel open and every five seconds with it closed, for the stall warning; rates are shown only in the open panel. Reading them starts no process. Captured test fixtures are synthetic or redacted.
- Raw CLI diagnostics are capped before they are shown.

Omarchy plugins run unsandboxed inside the long-lived `omarchy-shell` process with your user privileges. This plugin invokes `protonvpn` only after discovering it on `PATH`. Review the code before enabling it.

## Commands this plugin runs

Supervised by `scripts/run_bounded.py`, which caps output, enforces a deadline, and cleans up the process group. `protonvpn` runs also take the lock above:

- `/usr/bin/which protonvpn` to find the CLI
- `/usr/bin/git -c core.fsmonitor=false --no-optional-locks --git-dir=<plugin>/.git --work-tree=<plugin> status --porcelain=v2 --branch`, once when the plugin loads, a local read of the commit the plugin runs from, and whether its files changed, for the version line; it writes nothing and fails quietly outside a git checkout
- `protonvpn` subcommands: `--help`, `status`, `connect`, `disconnect`, `countries list`, `cities list`, `config list`, `config set`, and `signout`
- `/usr/bin/nmcli -t -e no -f NAME,TYPE,DEVICE,STATE,TIMESTAMP connection show --active`
- `/usr/bin/pacman -Q proton-vpn-cli`, `/usr/bin/pacman -Sddp --print-format "%n %r %v" proton-vpn-cli`, and `/usr/bin/stat -c %Y /var/lib/pacman/sync/<repo>.db`, local reads of the installed and latest known CLI version, at most once a minute when the panel opens
- `/usr/bin/checkupdates --nocolor`, only when you press **Check**; it asks your Arch mirrors in a temporary database of its own
- `/usr/bin/ip -j route get 1.1.1.1`, `/usr/bin/ip -j -6 route get 2606:4700:4700::1111`, and `/usr/bin/resolvectl --json=short status`, local reads for the tunnel check, only while connected; `/usr/bin/busctl --system --json=short list` as well, only when IPv6 seems to leave outside the tunnel, to see whether Proton's firewall Kill Switch runs

Read in place, without starting a process: `/sys/class/net/<device>/statistics/rx_bytes` and `tx_bytes`, only for a `proton0`-style device.

Started directly and kept running while the widget is loaded, with its output read one line at a time and discarded:

- `/usr/bin/nmcli monitor`, restarted with a backoff of up to a minute if it exits

Started directly, only when you press the matching panel control:

- `wl-copy` copies the suggested sign-in command
- `omarchy-launch-floating-terminal-with-presentation omarchy-update` opens Omarchy's system update when you press **Update**
- `omarchy-install-app "Proton VPN CLI" proton-vpn-cli` opens Omarchy's installer in a floating terminal
- `omarchy-launch-floating-terminal-with-presentation` with one fixed script, `read -rp 'Proton username: ' u && protonvpn signin -- "$u"`, for signing in. The script contains no values from the plugin.

Started directly when the tunnel changes while the panel is closed:

- `omarchy-notification-send` sends a fixed desktop notification when the tunnel drops (or connects, if enabled), when an automatic reconnect gives up, or when the tunnel check first finds traffic or DNS outside the tunnel. CLI-supplied server names only ever follow fixed text in the body. Clicking it runs `omarchy-shell io.github.BVisagie.protonvpn open`.
