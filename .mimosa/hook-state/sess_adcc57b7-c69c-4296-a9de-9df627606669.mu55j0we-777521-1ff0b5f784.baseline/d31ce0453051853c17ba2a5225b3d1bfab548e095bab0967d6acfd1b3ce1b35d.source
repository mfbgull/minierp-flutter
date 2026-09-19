#!/usr/bin/env bash
# Dev launcher: restarts the mini-ERP API server, then runs the Flutter app
# on Chrome (web) or the Linux desktop.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT/server"
FLUTTER="${FLUTTER:-/media/fawad/26F2EFA7F2EF7987/D/flutter/bin/flutter}"
PORT="${PORT:-3011}"
LOG="${SERVER_LOG:-/tmp/minierp-server.log}"
HEALTH_URL="http://localhost:${PORT}/api/health"

pids_on_port() {
  local pids
  pids="$(lsof -ti tcp:"$PORT" 2>/dev/null || true)"
  if [ -n "$pids" ]; then printf '%s\n' "$pids"; return; fi
  # lsof absent: parse ss
  pids="$(ss -tlnp 2>/dev/null | awk -v p=":$PORT " '$4 ~ p {match($0, /pid=([0-9]+)/, m); print m[1]}' | sort -u || true)"
  printf '%s\n' "$pids"
}

stop_server() {
  local pids
  pids="$(pids_on_port)"
  if [ -n "$pids" ]; then
    echo "→ Stopping server on :$PORT (pid: $pids)"
    kill $pids 2>/dev/null || true
  fi
  for _ in $(seq 1 10); do
    [ -z "$(pids_on_port)" ] && break
    sleep 0.5
  done
  pids="$(pids_on_port)"
  if [ -n "$pids" ]; then
    echo "→ Port $PORT still busy (pid: $pids) — SIGKILL"
    kill -9 $pids 2>/dev/null || true
    sleep 1
  fi
}

start_server() {
  cd "$SERVER_DIR"
  nohup node dist/server.js >"$LOG" 2>&1 &
  echo "→ Server started (pid $!) → log: $LOG"
  cd "$ROOT"
  for _ in $(seq 1 60); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$HEALTH_URL" 2>/dev/null || true)"
    [ "$code" != "000" ] && { echo "→ Server up on :$PORT (health: HTTP $code)"; return 0; }
    sleep 0.5
  done
  echo "✗ Server did not come up — check $LOG" >&2
  exit 1
}

echo "=== Mini ERP: restart server + run app ==="
echo "How do you want to run the app?"
echo "  1) Chrome (web)"
echo "  2) Linux desktop"
read -rp "Choice [1/2]: " choice
case "$choice" in
  1|web|chrome)   DEV="-d chrome"; TGT="Chrome";;
  2|desktop|linux) DEV="-d linux"; TGT="Linux desktop";;
  *) echo "Invalid choice: $choice" >&2; exit 1;;
esac

echo "=== [1/2] Restarting API server on :$PORT ==="
stop_server
start_server

if [ "${RUN_ONLY_SERVER:-0}" = "1" ]; then exit 0; fi

echo "=== [2/2] Launching app on $TGT ==="
cd "$ROOT"
exec "$FLUTTER" run $DEV
