# Release checklist

`./scripts/check.sh` cannot load the widget: Quickshell and Omarchy imports only
resolve inside `omarchy-shell`. Before tagging a release, load it in a real bar.

1. Run `./scripts/check.sh`. It must end with "All checks passed."
2. Install the branch over the plugin, for example by checking it out in
   `~/.config/omarchy/plugins/io.github.BVisagie.protonvpn/`. Saving there
   reloads the widget. Reloading the widget leaves an existing tunnel up.
3. Watch `journalctl --user -f` (or the terminal running `omarchy-shell`) for
   QML errors while the widget loads.
4. Check, with the panel open and closed:
   - the bar icon and tooltip for connected and disconnected;
   - the panel opens, the keyboard cursor moves through every row, and `Esc`
     closes it;
   - SETTINGS folds open and closed, and every value matches
     `protonvpn config list`;
   - Quick connect lists favourites and recents, and `f` stars a row;
   - a desktop notification arrives when the tunnel goes down while the panel is
     closed (only when it is safe to drop the VPN);
   - `omarchy-shell io.github.BVisagie.protonvpn statusJson` prints JSON.
5. Switch Setup > Language to another language and back; the panel follows
   without a restart.
6. Try a vertical bar (`omarchy bar position left`) and move it back.
7. Bump `manifest.json`, `tests/manifest.test.js`, and `CHANGELOG.md` together.
