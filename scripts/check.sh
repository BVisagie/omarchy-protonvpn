#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  echo "check failed: $*" >&2
  exit 1
}

echo "==> Node tests"
node --test tests/model.test.js tests/scheduler.test.js tests/qml-contract.test.js

echo "==> Manifest validation"
if ! command -v omarchy >/dev/null 2>&1; then
  fail "omarchy is not on PATH"
fi
omarchy plugin validate .

echo "==> QML files present"
for file in Panel.qml Service.qml ProtonVpnIcon.qml Model.js Scheduler.js; do
  [[ -s "$file" ]] || fail "missing $file"
done

echo "==> Meaningful QML validation"
qmlint_bin=""
if command -v qmllint >/dev/null 2>&1; then
  qmlint_bin="$(command -v qmllint)"
elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  qmlint_bin="/usr/lib/qt6/bin/qmllint"
fi

if [[ -n "$qmlint_bin" ]]; then
  include=()
  if [[ -n "${OMARCHY_PATH:-}" && -d "$OMARCHY_PATH/shell" ]]; then
    include=(-I "$OMARCHY_PATH/shell")
  elif [[ -d /usr/share/omarchy/shell ]]; then
    include=(-I /usr/share/omarchy/shell)
  fi
  # Unresolved Quickshell/Omarchy imports are expected outside omarchy-shell.
  # Fail only on syntax/parse errors, not the import-resolution warning flood.
  report="$(mktemp)"
  set +e
  "$qmlint_bin" "${include[@]}" Panel.qml Service.qml ProtonVpnIcon.qml >"$report" 2>&1
  set -e
  if grep -Ei 'syntax error|invalid token|unexpected token|Expected token' "$report" >/dev/null; then
    echo "qmllint reported syntax errors:" >&2
    grep -Ei 'syntax error|invalid token|unexpected token|Expected token' "$report" >&2
    rm -f "$report"
    fail "qmllint syntax"
  fi
  rm -f "$report"
  echo "qmllint: no syntax errors (import-resolution warnings ignored)"
else
  echo "qmllint not installed; skipped binary lint"
fi

echo "==> Shell-load smoke"
node -e "require('./Model.js'); require('./Scheduler.js'); if (!require('./Model.js').canWrite || !require('./Scheduler.js').enqueueJob) process.exit(1)"
python - "$root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for name in ("Panel.qml", "Service.qml", "ProtonVpnIcon.qml"):
    text = (root / name).read_text(encoding="utf-8")
    if text.count("{") != text.count("}"):
        raise SystemExit(f"{name} brace mismatch")
    if "import QtQuick" not in text:
        raise SystemExit(f"{name} missing QtQuick import")
print("qml smoke: brace balance and QtQuick imports ok")
PY

echo "All checks passed."
