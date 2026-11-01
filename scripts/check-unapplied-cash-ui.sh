#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
RUN="$(mktemp -d "$ROOT/server/.tmp-test/ui-f7-run-XXXXXX")"
DIRECTORY=''
PID=''
DISPLAY_PID=''
WM_PID=''
cleanup() {
  if [[ -n "$WM_PID" ]]; then
    kill -TERM "$WM_PID" 2>/dev/null || true
    wait "$WM_PID" 2>/dev/null || true
  fi
  if [[ -n "$DISPLAY_PID" ]]; then
    kill -TERM "$DISPLAY_PID" 2>/dev/null || true
    wait "$DISPLAY_PID" 2>/dev/null || true
  fi
  if [[ -n "$PID" ]]; then
    kill -TERM "$PID" 2>/dev/null || true
    wait "$PID" || true
  fi
  if [[ -n "$DIRECTORY" && "$DIRECTORY" == "$ROOT/server/.tmp-test/ui-f7-"* && -f "$DIRECTORY/fixture-id" ]]; then
    rm -rf -- "$DIRECTORY"
  fi
  printf 'Runtime evidence: %s\n' "$RUN"
}
trap cleanup EXIT

# Run the suite on a private virtual display so the Flutter window never covers
# the developer's desktop and never steals pointer or keyboard focus.
# Set MINIERP_UI_DISPLAY to target an existing display instead. Use :0 only
# when you accept that the test windows take over the active desktop.
start_isolated_display() {
  if [[ -n "${MINIERP_UI_DISPLAY:-}" ]]; then
    export DISPLAY="$MINIERP_UI_DISPLAY"
    printf 'Using requested display %s\n' "$DISPLAY"
    return
  fi
  if [[ -z "$(command -v Xvfb || true)" ]]; then
    printf 'Xvfb is not installed; the UI windows will use the active desktop.\n' >&2
    printf 'Install it with: sudo apt install xvfb\n' >&2
    return
  fi
  local number=''
  local candidate
  for candidate in $(seq 99 109); do
    if [[ ! -e "/tmp/.X11-unix/X$candidate" ]]; then
      number="$candidate"
      break
    fi
  done
  if [[ -z "$number" ]]; then
    printf 'No free display number in the range :99-:109\n' >&2
    exit 1
  fi
  Xvfb ":$number" -screen 0 1600x900x24 -nolisten tcp -ac -noreset \
    >"$RUN/xvfb.log" 2>&1 &
  DISPLAY_PID=$!
  for _ in $(seq 1 50); do
    [[ -e "/tmp/.X11-unix/X$number" ]] && break
    kill -0 "$DISPLAY_PID" 2>/dev/null || break
    sleep 0.2
  done
  if [[ ! -e "/tmp/.X11-unix/X$number" ]]; then
    printf 'Could not start Xvfb on :%s\n' "$number" >&2
    exit 1
  fi
  export DISPLAY=":$number"
  printf 'UI display %s (resolution 1600x900)\n' "$DISPLAY"
  if [[ -n "$(command -v metacity || true)" ]]; then
    metacity --display="$DISPLAY" >"$RUN/wm.log" 2>&1 &
    WM_PID=$!
    sleep 1
  fi
}
start_isolated_display

if curl --silent --fail -H 'X-Fixture-Token: mini-erp-f7-local' http://127.0.0.1:4328/health >/dev/null 2>&1; then
  printf 'An isolated fixture is already running; refusing to reuse it.\n' >&2
  exit 1
fi
node server/scripts/fixtures/unapplied-cash-ui.cjs >"$RUN/server.log" 2>&1 &
PID=$!
for attempt in $(seq 1 120); do
  kill -0 "$PID"
  if curl --silent --fail -H 'X-Fixture-Token: mini-erp-f7-local' http://127.0.0.1:4328/health >"$RUN/health.json"; then
    break
  fi
  sleep 1
done
DIRECTORY="$(node -e "const fs=require('fs');const health=JSON.parse(fs.readFileSync(process.argv[1]));const lines=fs.readFileSync(process.argv[2],'utf8').trim().split('\n');const ready=JSON.parse(lines.at(-1));if(health.fixture!=='mini-erp-unapplied-cash-f7'||health.api!=='http://127.0.0.1:4327/api'||health.marker!==ready.marker||health.directory!==ready.directory)throw Error('Not the owned isolated fixture');process.stdout.write(health.directory)" "$RUN/health.json" "$RUN/server.log")"
export XDG_DATA_HOME="$DIRECTORY/app-data"
export XDG_CONFIG_HOME="$DIRECTORY/app-config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
for phase in journeys lost resume; do
  printf 'Running native cash UI phase: %s\n' "$phase"
  if ! flutter test integration_test/unapplied_cash_flow_test.dart -d linux --no-pub --dart-define="F7_PHASE=$phase" >"$RUN/$phase.log" 2>&1; then
    tail -60 "$RUN/$phase.log"
    exit 1
  fi
  tail -4 "$RUN/$phase.log"
done
curl --silent --fail -H 'X-Fixture-Token: mini-erp-f7-local' http://127.0.0.1:4328/status >"$RUN/status.json"
node -e "const data=JSON.parse(require('fs').readFileSync(process.argv[1]));if(!data.canonicalUnchanged||data.gl.groups.length||Math.abs(data.gl.totalDiff)>0.001||Object.values(data.violations).some(rows=>rows.length))throw Error('Final invariant failure');console.log('PASS final accounting invariants and canonical fingerprints')" "$RUN/status.json"
