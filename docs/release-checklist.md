# Release checklist

`./scripts/check.sh` cannot load the widget: Quickshell and Omarchy imports only
resolve inside `omarchy-shell`. Before tagging a release, load it in a real bar.

1. Run `./scripts/check.sh`. It must end with "All checks passed."
   Then run `./scripts/load-smoke.sh`, which loads the service and panel in a
   throwaway Quickshell instance and fails on QML errors. It runs only
   read-only probes (Proton, NetworkManager, and with a tunnel up the routing
   check, which can notify about a leak it finds).
2. Install the branch over the plugin, for example by checking it out in
   `~/.config/omarchy/plugins/io.github.BVisagie.protonvpn/`. Saving there
   reloads the widget. Reloading the widget leaves an existing tunnel up.
3. Watch `journalctl --user -f` (or the terminal running `omarchy-shell`) for
   QML errors while the widget loads.
4. Check, with the panel open and closed:
   - the bar icon and tooltip for connected and disconnected;
   - the panel opens, the keyboard cursor moves through every row, and `Esc`
     closes it (with a tooltip showing, the first `Esc` hides the tooltip);
   - the foot of the panel reads "Plugin <version> · <commit>", with
     ", modified" after you change a tracked file;
   - SETTINGS folds open and closed, and every value matches
     `protonvpn config list`;
   - QUICK CONNECT lists favorites and recents by full name, and `f` stars a row;
   - SETTINGS fits without scrolling in a usual state (connected, five QUICK
     CONNECT rows), and the footer shows the CLI version;
   - a desktop notification arrives when the tunnel goes down while the panel is
     closed (only when it is safe to drop the VPN);
   - `omarchy-shell io.github.BVisagie.protonvpn statusJson` prints JSON, and
     while connected its `routing` reads `ok` for ipv4 and dns, and for ipv6
     `ok`, `none` without IPv6, `blocked` with the CLI's IPv6 setting off, or
     `unknown` while the firewall Kill Switch runs, with no tunnel-check warning
     in the panel.
5. Switch Setup > Language to another language and back; the panel follows
   without a restart.
6. Try a vertical bar (`omarchy bar position left`) and move it back.
7. Every merge to `main` reaches installs, so any pull request that changes
   shipped code bumps the version: `manifest.json`, `VERSION` in `Model.js`, and
   `CHANGELOG.md` together. After merging, tag the commit `v<version>` and date
   its changelog entry.
