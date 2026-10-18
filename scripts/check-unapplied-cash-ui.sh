#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
RUN="$(mktemp -d "$ROOT/server/.tmp-test/ui-f7-run-XXXXXX")"
DIRECTORY=''
PID=''
cleanup() {
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
