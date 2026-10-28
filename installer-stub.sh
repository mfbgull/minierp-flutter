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
