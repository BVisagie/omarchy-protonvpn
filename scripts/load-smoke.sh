#!/usr/bin/env bash
# Load Service.qml and Panel.qml in a throwaway Quickshell instance, outside
# omarchy-shell, and fail on QML errors. It opens no window, and the service
# runs only its read-only probes (which, protonvpn status/--help/config list,
# countries list, nmcli). It never connects, disconnects, or changes settings.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
command -v quickshell >/dev/null || { echo "quickshell is not installed" >&2; exit 1; }
[[ -d $shell_dir/Commons ]] || { echo "Omarchy shell sources not found at $shell_dir" >&2; exit 1; }

harness="$(mktemp -d)"
trap 'rm -rf "$harness"' EXIT
for dir in Commons Ui services; do ln -s "$shell_dir/$dir" "$harness/$dir"; done
ln -s "$root" "$harness/plugin"
cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugin" as P

ShellRoot {
  P.Service { id: svc }
  Item { P.Panel { id: panel } }
  Timer {
    interval: 9000
    running: true
    onTriggered: {
      console.log("SMOKE state=" + svc.state + " link=" + svc.linkActive + " config=" + svc.configLoaded
        + " panel=" + panel.view.state)
      Qt.quit()
    }
  }
}
QML

log="$(timeout 30 quickshell -p "$harness/shell.qml" 2>&1 || true)"
grep -E "SMOKE|ERROR|TypeError|ReferenceError|is not a type|is not defined" <<<"$log" || true
grep -q 'SMOKE state=' <<<"$log" || { echo "load smoke: the harness never reported" >&2; exit 1; }
if grep -Eq 'ERROR|TypeError|ReferenceError|is not a type|is not defined' <<<"$log"; then
  echo "load smoke: QML errors above" >&2
  exit 1
fi
echo "load smoke: Service.qml and Panel.qml load"
