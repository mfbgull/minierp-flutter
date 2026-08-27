#!/usr/bin/env bash
# ============================================================================
# MiniERP — Linux single-file setup builder
# Produces: build/minierp-setup-<VERSION>.run
#   A self-contained installer with:
#     • Flutter Linux release bundle (UI)
#     • Node.js server (backend) + bundled Node runtime
#     • SQLite DB (existing data optional; --fresh omits)
# Usage:
#   ./tool/make_linux_setup.sh               # full build
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
NODE_VERSION="$($NODE --version | cut -d' ' -f2 | sed 's/^v//')"
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
echo "  version: $VERSION | node: $NODE_VERSION | data: $WITH_DATA"

# -------------------------------------------------
#   1. Build Flutter release bundle (if needed)
# -------------------------------------------------
echo "[1/5] Building Flutter release bundle..."
if [ "$DO_BUILD" = 1 ]; then
  "$FLUTTER" build linux --release
fi
BUNDLE="$ROOT/build/linux/x64/release/bundle"
[ -f "$BUNDLE/minierp_app" ] || { echo "✗ release bundle missing at $BUNDLE"; exit 1; }

# -------------------------------------------------
#   2. Build server (if needed)
# -------------------------------------------------
echo "[2/5] Building server backend..."
if [ "$DO_BUILD" = 1 ]; then
  (cd server && npm run build)
fi
[ -f server/dist/server.js ] || { echo "✗ server backend missing"; exit 1; }

# -------------------------------------------------
#   3. Stage layout
# -------------------------------------------------
echo "[3/5] Staging files..."
STAGE="$ROOT/build/setup-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/minierp/server" "$STAGE/minierp/runtime" "$STAGE/.cache"

# copy UI bundle -> minierp/bundle (no nesting)
cp -a "$BUNDLE" "$STAGE/minierp/bundle"

# copy built server (defense-in-depth: never ship source maps or TS sources)
cp -a server/dist "$STAGE/minierp/server/dist"
find "$STAGE/minierp/server/dist" \( -name '*.map' -o -name '*.ts' \) -delete
cp server/package.json server/package-lock.json "$STAGE/minierp/server/"
cp -a server/uploads "$STAGE/minierp/server/uploads"
mkdir -p "$STAGE/minierp/server/logs"

# prune dev deps in staged copy (node_modules may be huge)
echo "[3.1/5] Pruning dev dependencies..."
cp -a server/node_modules "$STAGE/minierp/server/node_modules"
(cd "$STAGE/minierp/server" && npm prune --omit=dev --no-audit --no-fund >/dev/null)
# Drop unused sqlite3 native module (not used by any server code)
rm -rf "$STAGE/minierp/server/node_modules/sqlite3"
# Runtime never reads type declarations or source maps — drop them
rm -rf "$STAGE/minierp/server/node_modules/@types"
find "$STAGE/minierp/server/node_modules" \( -name '*.map' -o -name '*.d.ts' \) -delete

# -------------------------------------------------
#   3.1 Database (optional, with WAL checkpoint)
# -------------------------------------------------
if [ "$WITH_DATA" = 1 ] && [ -f server/database/erp.db ]; then
  echo "[3.2/5] Packing existing DB (WAL checkpoint prepare)..."
  mkdir -p "$STAGE/minierp/server/database"
  (cd server && "$NODE" -e "
    const D=require('better-sqlite3');
    const db=new D('database/erp.db');
    db.pragma('wal_checkpoint(TRUNCATE)');
    db.pragma('optimize');
    db.close();
  ")
  cp server/database/erp.db "$STAGE/minierp/server/database/erp.db"
else
  echo "[3.2/5] Fresh install: no DB shipped — schema auto-initializes on first run"
fi

# -------------------------------------------------
#   4. .env file
# -------------------------------------------------
echo "[4/5] Generating server/.env"
JWT="$(openssl rand -hex 32 2>/dev/null || head -c64 /dev/urandom | od -An -tx1 | tr -d ' \n')"
cat > "$STAGE/minierp/server/.env" <<EOF
PORT=3011
HOST=0.0.0.0
NODE_ENV=production
JWT_SECRET=$JWT
DEFAULT_ADMIN_PASSWORD=admin123
ALLOWED_ORIGINS=http://localhost:3011,http://127.0.0.1:3011,file://
EOF

# -------------------------------------------------
#   5. Bundle Node Node.js runtime
# -------------------------------------------------
echo "[5/5] Bundling bundled Node $($NODE --version)"
CACHE="$ROOT/build/.cache/node-$NODE_VERSION-linux-x64.tar.xz"
mkdir -p "$(dirname "$CACHE")"
[ -f "$CACHE" ] || curl -fL --retry 3 -o "$CACHE" "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz"
mkdir -p "$STAGE/minierp/runtime"
tar -xJf "$CACHE" -C "$STAGE/minierp/runtime" "node-v$NODE_VERSION-linux-x64/bin/node"
mv "$STAGE/minierp/runtime/node-v$NODE_VERSION-linux-x64/bin/node" "$STAGE/minierp/runtime/node"
rm -rf "$STAGE/minierp/runtime/node-v$NODE_VERSION-linux-x64"
chmod +x "$STAGE/minierp/runtime/node"

# -------------------------------------------------
#   6. Final sanity check: bundled Node + better-sqlite3
# -------------------------------------------------
echo "[6/5] Verifying bundled Node + better-sqlite3 ABI..."
"$STAGE/minierp/runtime/node" -e "
  const D=require('$STAGE/minierp/server/node_modules/better-sqlite3');
  const db=new D(':memory:'); db.exec('CREATE TABLE t(x)'); db.close();
  console.log('  ✅ bundled Node', process.version, 'loads better-sqlite3 OK');
"

# -------------------------------------------------
#   8. Desktop entry (in payload only; stub substitutes placeholder)
# -------------------------------------------------
echo "[8/5] Writing launcher minierp..."
cat > "$STAGE/minierp/minierp" <<'LAUNCHER'
#!/usr/bin/env bash
# MiniERP launcher.
set -euo pipefail
APP_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
SERVER_DIR="$APP_DIR/server"
NODE="$APP_DIR/runtime/node"
PORT="${PORT:-3011}"
HEALTH_URL="http://127.0.0.1:${PORT}/health"
PID_FILE="$APP_DIR/server.pid"

server_running() {
  curl -sf --max-time 2 "$HEALTH_URL" >/dev/null 2>&1
}

start_server() {
  if server_running; then return 0; fi
  cd "$SERVER_DIR"
  # DR-04 (audit-remediation 6.3): tracked process group + graceful trap so
  # SIGTERM reaches the server and it can checkpoint WAL + flush audit logs.
  cd "$SERVER_DIR"
  setsid "$NODE" dist/server.js >"$SERVER_DIR/logs/server.log" 2>&1 &
  SERVER_PID=$!
  trap '
    kill -TERM -- -'"$SERVER_PID"' 2>/dev/null
    for i in 1 2 3 4 5 6; do
      kill -0 '"$SERVER_PID"' 2>/dev/null || break
      sleep 0.5
    done
    # Backstop after the 3s grace window
    kill -9 -- -'"$SERVER_PID"' 2>/dev/null
  ' EXIT INT TERM
  echo $! > "$PID_FILE"
  for _ in $(seq 1 60); do
    server_running && { echo "✓ API server ready on :$PORT"; return 0; }
    sleep 0.5
  done
  echo "✗ API server failed to start — see $SERVER_DIR/logs/error.log" >&2
  return 1
}

case "${1:-}" in
  stop) [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null || true; \
        pkill -f "$SERVER_DIR/dist/server.js" 2>/dev/null || true; \
        rm -f "$PID_FILE"; echo "✓ API server stopped";;
  status) if server_running; then echo "API server: RUNNING ($HEALTH_URL)"; else echo "API server: STOPPED"; fi;;
  *) start_server; exec "$APP_DIR/bundle/minierp_app";;
esac
LAUNCHER
chmod +x "$STAGE/minierp/minierp" || true

# -------------------------------------------------
#   8. Desktop entry
# -------------------------------------------------
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

# -------------------------------------------------
#   9. Assemble self‑extracting installer
# -------------------------------------------------
echo "[8/5] Building the .run installer..."
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

# Empty on fresh installs; set to a backup dir on the upgrade path below.
UPGRADE_TMP=""

if [ -e "$DIR" ]; then
  if [ "$FORCE" != 1 ]; then
    echo "✗ $DIR already exists — re‑run with --force to overwrite." >&2; exit 1
  fi

  # DR-07 (audit-remediation 7.5): upgrade path — back up existing database,
  # uploads and .env before any removal, then restore them into the new install.
  UPGRADE_TMP="$(mktemp -d)"
  if [ -d "$DIR/server/database" ]; then
    mkdir -p "$UPGRADE_TMP/database"
    cp -a "$DIR/server/database/." "$UPGRADE_TMP/database/" 2>/dev/null || true
  fi
  [ -d "$DIR/server/uploads" ] && cp -a "$DIR/server/uploads" "$UPGRADE_TMP/uploads" 2>/dev/null
  [ -f "$DIR/server/.env" ] && cp -a "$DIR/server/.env" "$UPGRADE_TMP/env" 2>/dev/null

  rm -rf "$DIR";
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "📦 Extracting MiniERP…"
MARKER_OFFSET=$(grep -abo '__PAYLOAD_BELOW__' "$0" | tail -n1 | cut -d: -f1)
tail -c +"$((MARKER_OFFSET + 20))" "$0" | tar -xzf - -C "$TMP"
mkdir -p "$(dirname "$DIR")"
mv "$TMP/minierp" "$DIR"
chmod +x "$DIR/bundle/minierp_app" "$DIR/runtime/node" "$DIR/minierp" 2>/dev/null || true
# Restore upgraded data (7.5): user data survives the reinstall; only the
# shipped placeholder DB is removed (including any -wal/-shm remnants).
rm -f "$DIR/server/database/erp.db" "$DIR/server/database/erp.db-wal" "$DIR/server/database/erp.db-shm"
if [ -n "$UPGRADE_TMP" ] && [ -d "$UPGRADE_TMP/database" ] && compgen -G "$UPGRADE_TMP/database/*" > /dev/null; then
  mkdir -p "$DIR/server/database"
  cp -a "$UPGRADE_TMP/database/." "$DIR/server/database/"
  echo "↩ Restored existing database from previous install"
fi
[ -f "$UPGRADE_TMP/env" ] && cp -a "$UPGRADE_TMP/env" "$DIR/server/.env" && echo "↩ Restored server/.env"
[ -d "$UPGRADE_TMP/uploads" ] && cp -a "$UPGRADE_TMP/uploads" "$DIR/server/" && echo "↩ Restored uploads"
[ -n "$UPGRADE_TMP" ] && rm -rf "$UPGRADE_TMP"

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
echo "   Stop server:    minierp stop"
echo "   View logs:      tail -f $DIR/server/logs/server.log"
echo "   Remove:         rm -rf $DIR $HOME/.local/bin/minierp $HOME/.local/share/applications/minierp.desktop"
exit 0
: "__PAYLOAD_BELOW__"
STUB

# Build final single‑file installer
cat "$ROOT/installer-stub.sh" "$PAYLOAD" > "$OUT"
chmod +x "$OUT"
echo ""
echo "🚀 Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo "   Install with:   ./$(basename "$OUT") [options]"
