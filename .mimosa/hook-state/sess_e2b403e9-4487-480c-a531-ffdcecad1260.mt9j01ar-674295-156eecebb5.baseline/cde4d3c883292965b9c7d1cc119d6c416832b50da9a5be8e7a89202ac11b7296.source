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
