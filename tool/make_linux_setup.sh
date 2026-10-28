#!/usr/bin/env bash
# ============================================================================
# MiniERP — Linux single-file setup builder
# Produces: build/minierp-setup-<VERSION>.run
#
# Every installer is self-contained: the Flutter client, the compiled server,
# its production node_modules, and a pinned Node runtime. The Flutter app
# starts and stops the server itself (it is not launched by this script).
#
# Layout on disk after install:
#   <DIR>/app/bundle/minierp_app     Flutter client
#   <DIR>/app/server/               server + runtime/node
#   <DIR>/data/                     database, uploads, logs, .env
#   <DIR>/minierp                   launcher (sets MINIERP_DATA_DIR)
#
# Usage:
#   ./tool/make_linux_setup.sh               # full build, ships existing DB
#   ./tool/make_linux_setup.sh --fresh       # ship WITHOUT existing DB data
#   ./tool/make_linux_setup.sh --no-build    # reuse existing build artifacts
#   ./tool/make_linux_setup.sh --out <path>  # custom output file
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Guard against concurrent runs: a second invocation would `rm -rf` the
# staging dir mid-flight and corrupt the first run's output.
LOCK_FILE="$ROOT/build/.make_linux_setup.lock"
mkdir -p "$ROOT/build"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "ERROR: another make_linux_setup.sh run is already in progress." >&2
  exit 1
fi

# ----- options ---------------------------------------------------------------
VERSION="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
FLUTTER="${FLUTTER:-flutter}"
NODE="${NODE:-node}"
WITH_DATA=1
DO_BUILD=1
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fresh)   WITH_DATA=0; shift;;
    --no-build) DO_BUILD=0; shift;;
    --out)     OUT="$2"; shift 2;;
    *) echo "Unknown option: $1 (try --help)"; exit 1;;
  esac
done
OUT="${OUT:-$ROOT/build/minierp-setup-$VERSION.run}"

echo "=== MiniERP builder $(date) ==="
echo "  version: $VERSION | node: $($NODE --version) | data: $WITH_DATA"

# -------------------------------------------------
#   1. Flutter release bundle
# -------------------------------------------------
echo "[1/4] Building Flutter release bundle..."
if [ "$DO_BUILD" = 1 ]; then
  "$FLUTTER" build linux --release
fi
BUNDLE="$ROOT/build/linux/x64/release/bundle"
[ -f "$BUNDLE/minierp_app" ] || { echo "✗ release bundle missing at $BUNDLE"; exit 1; }

# -------------------------------------------------
#   2. Server build
# -------------------------------------------------
echo "[2/4] Building server backend..."
if [ "$DO_BUILD" = 1 ]; then
  (cd server && npm ci && npm run build)
fi
[ -f server/dist/server.js ] || { echo "✗ server backend missing (run npm run build in server/)"; exit 1; }

# -------------------------------------------------
#   3. Stage: app/{bundle,server} + data/{database}
# -------------------------------------------------
echo "[3/4] Staging self-contained app tree..."
STAGE="$ROOT/build/setup-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/minierp/app" "$STAGE/minierp/data"

cp -a "$BUNDLE" "$STAGE/minierp/app/bundle"

# Compiled server + production deps + pinned runtime, all built for this OS.
"$NODE" "$ROOT/tool/stage-server.mjs" \
  --dist "$ROOT/server/dist" \
  --out "$STAGE/minierp/app/server"

# The staging script creates empty database/uploads/logs directories for
# standalone use; inside the package those live under <DIR>/data instead.
rm -rf "$STAGE/minierp/app/server/database" \
       "$STAGE/minierp/app/server/uploads" \
       "$STAGE/minierp/app/server/logs"

# Optional: ship an existing database (--fresh skips it).
if [ "$WITH_DATA" = 1 ] && [ -f server/database/erp.db ]; then
  echo "[3.1/4] Packing existing DB (WAL checkpoint prepare)..."
  mkdir -p "$STAGE/minierp/data/database"
  (cd server && "$NODE" -e "
    const D=require('better-sqlite3');
    const db=new D('database/erp.db');
    db.pragma('wal_checkpoint(TRUNCATE)');
    db.pragma('optimize');
    db.close();
  ")
  cp server/database/erp.db "$STAGE/minierp/data/database/erp.db"
else
  echo "[3.1/4] Fresh install: no DB shipped — first launch asks for the admin password"
fi

# -------------------------------------------------
#   4. Launcher + desktop entry
# -------------------------------------------------
echo "[4/4] Writing launcher and assembling the installer..."
cat > "$STAGE/minierp/minierp" <<'LAUNCHER'
#!/usr/bin/env bash
# MiniERP launcher. The app supervises the bundled server itself; this script
# only points it at the data directory and keeps stop/status for recovery.
set -euo pipefail
APP_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
DATA_DIR="$APP_DIR/data"
PID_FILE="$DATA_DIR/server.pid"

server_pid() {
  [ -f "$PID_FILE" ] && cat "$PID_FILE" 2>/dev/null || true
}

case "${1:-}" in
  stop)
    pid="$(server_pid)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 60); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -KILL "$pid" 2>/dev/null || true
      echo "✓ MiniERP server stopped"
    else
      echo "MiniERP server is not running"
    fi
    rm -f "$PID_FILE"
    ;;
  status)
    pid="$(server_pid)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "MiniERP server: RUNNING (pid $pid)"
    else
      echo "MiniERP server: STOPPED"
    fi
    ;;
  *)
    mkdir -p "$DATA_DIR"
    MINIERP_DATA_DIR="$DATA_DIR" exec "$APP_DIR/app/bundle/minierp_app" "$@"
    ;;
esac
LAUNCHER
chmod +x "$STAGE/minierp/minierp"

cat > "$STAGE/minierp/minierp.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=MiniERP
Comment=Mini ERP — Inventory, Sales, Production
Exec=__APP_DIR__/minierp
Path=__APP_DIR__
Terminal=false
Categories=Office;Finance;Business;
StartupWMClass=minierp_app
DESKTOP

PAYLOAD="$ROOT/build/setup-payload.tar.gz"
tar -czf "$PAYLOAD" -C "$STAGE" minierp >/dev/null

# stub script (cat to stdout)
cat > "$ROOT/installer-stub.sh" <<'STUB'
#!/usr/bin/env bash
# MiniERP single‑file installer.
#   ./minierp-setup-<ver>.run [--dir PATH] [--force] [--no-desktop]
set -euo pipefail
DIR_DEFAULT="$HOME/.local/share/minierp"
DIR="$DIR_DEFAULT"; FORCE=0; DESKTOP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)       DIR="$2"; shift 2;;
    --force)     FORCE=1; shift;;
    --no-desktop) DESKTOP=0; shift;;
    -h|--help)   grep -m4 '^#' "$0" | sed 's/^# //'; exit 0;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

# A previous install of the old layout (bundle/, server/, runtime/ at the top
# level) or the current one (app/) both get replaced; <DIR>/data is preserved.
if [ -e "$DIR/app" ] || [ -e "$DIR/bundle" ]; then
  if [ "$FORCE" != 1 ]; then
    echo "✗ $DIR already exists — re‑run with --force to overwrite." >&2; exit 1
  fi
fi
if [ -e "$DIR" ] && [ ! -d "$DIR" ]; then
  echo "✗ $DIR is not a directory." >&2; exit 1
fi

# Migrate data written by the legacy layout into <DIR>/data before replacing
# the app tree. Existing data wins over anything shipped in the package.
mkdir -p "$DIR/data"
if [ -d "$DIR/server/database" ] && [ ! -e "$DIR/data/database/erp.db" ]; then
  mkdir -p "$DIR/data/database"
  cp -a "$DIR/server/database/." "$DIR/data/database/" 2>/dev/null || true
  echo "↩ Migrated database from the previous install"
fi
if [ -d "$DIR/server/uploads" ] && [ ! -d "$DIR/data/uploads" ]; then
  cp -a "$DIR/server/uploads" "$DIR/data/uploads" 2>/dev/null || true
fi
# Keep the signing secret (it keys stored encryption), but never carry the
# legacy DEFAULT_ADMIN_PASSWORD: current packages pass it only for the first
# boot, so a persisted copy would be a stale credential on disk.
if [ -f "$DIR/server/.env" ] && [ ! -f "$DIR/data/.env" ]; then
  grep -v '^DEFAULT_ADMIN_PASSWORD=' "$DIR/server/.env" > "$DIR/data/.env" || true
  chmod 600 "$DIR/data/.env" 2>/dev/null || true
fi

rm -rf "$DIR/app" "$DIR/bundle" "$DIR/runtime" "$DIR/server" \
       "$DIR/minierp" "$DIR/minierp.desktop"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "📦 Extracting MiniERP…"
MARKER_OFFSET=$(grep -abo '__PAYLOAD_BELOW__' "$0" | tail -n1 | cut -d: -f1)
tail -c +"$((MARKER_OFFSET + 20))" "$0" | tar -xzf - -C "$TMP"
mkdir -p "$DIR"
cp -a "$TMP/minierp/app" "$DIR/app"
cp -a "$TMP/minierp/minierp" "$DIR/minierp"
cp -a "$TMP/minierp/minierp.desktop" "$DIR/minierp.desktop"

# Shipped data is only a seed: never overwrite a database the user already has.
if [ -d "$TMP/minierp/data" ]; then
  (cd "$TMP/minierp/data" && find . -type f) | while read -r rel; do
    if [ ! -e "$DIR/data/$rel" ]; then
      mkdir -p "$DIR/data/$(dirname "$rel")"
      cp -a "$TMP/minierp/data/$rel" "$DIR/data/$rel"
    fi
  done
fi

chmod +x "$DIR/app/bundle/minierp_app" "$DIR/app/server/runtime/node" "$DIR/minierp" 2>/dev/null || true

mkdir -p "$HOME/.local/bin"
ln -sf "$DIR/minierp" "$HOME/.local/bin/minierp"

if [ "$DESKTOP" = 1 ]; then
  mkdir -p "$HOME/.local/share/applications"
  sed "s|__APP_DIR__|$DIR|g" "$DIR/minierp.desktop" > "$HOME/.local/share/applications/minierp.desktop"
  chmod +x "$HOME/.local/share/applications/minierp.desktop" 2>/dev/null || true
fi

echo ""
echo "✅ MiniERP installed → $DIR"
echo "   Launch with:   minierp            (or $DIR/minierp)"
echo "   Server status:  minierp status"
echo "   Stop server:    minierp stop"
echo "   Data:           $DIR/data  (survives upgrades)"
echo "   Remove:         rm -rf $DIR $HOME/.local/bin/minierp $HOME/.local/share/applications/minierp.desktop"
exit 0
: "__PAYLOAD_BELOW__"
STUB

cat "$ROOT/installer-stub.sh" "$PAYLOAD" > "$OUT"
chmod +x "$OUT"
echo ""
echo "🚀 Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo "   Install with:   ./$(basename "$OUT") [options]"
