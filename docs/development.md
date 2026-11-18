# Development

## Architecture

- `Service.qml` is the Omarchy service shared by every monitor. It runs Proton CLI commands one at a time and stops a stuck one with a watchdog.
- `Scheduler.js` is the job queue behind it. User actions and city lists go ahead of background refreshes, each job has its own timeout, and output from a job that was already stopped is ignored.
- `Panel.qml` contains the compact bar control and reads state from the shared service. When the bar cannot provide one, it runs a local `Service` instance instead.
- `ProtonVpnIcon.qml` draws the Proton VPN mark in the current theme color for the bar and panel.
- `Model.js` contains parsers, validation, compatibility detection, and display rules covered by captured fixtures.
- `scripts/run_bounded.py` is a local process supervisor and lock; it does not implement VPN behavior or make network requests.
- `i18n/` holds the translation catalogs; `tests/tools/build_catalog.js` regenerates `en.json` from the code.

## Validate the plugin

```sh
./scripts/check.sh
```

That script runs the Node and Python tests, `omarchy plugin validate` on a copy of the files a clone would contain (when Omarchy is installed), a check that no tracked file is a symlink, a QML contract check, a `qmllint` syntax check with a two-minute limit, and shell-load smoke tests. The same portable checks run in GitHub Actions. `qmllint` reports many unresolved-import warnings because Quickshell and Omarchy imports only resolve inside `omarchy-shell`. The script ignores those and fails only on syntax errors, so a pass does not prove the widget loads.

```sh
./scripts/load-smoke.sh
```

That loads the service and panel in a throwaway Quickshell instance, outside `omarchy-shell`, and fails on QML errors. It runs only read-only Proton and NetworkManager probes. Then test the widget in the bar before releasing; [release-checklist.md](release-checklist.md) lists what to check.
