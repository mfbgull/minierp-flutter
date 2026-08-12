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

if [ -e "$DIR" ]; then
  if [ "$FORCE" = 1 ]; then
    rm -rf "$DIR";
  else
    echo "✗ $DIR already exists — re‑run with --force to overwrite." >&2; exit 1
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "📦 Extracting MiniERP…"
MARKER_OFFSET=$(grep -abo '__PAYLOAD_BELOW__' "$0" | tail -n1 | cut -d: -f1)
tail -c +"$((MARKER_OFFSET + 20))" "$0" | tar -xzf - -C "$TMP"
mkdir -p "$(dirname "$DIR")"
mv "$TMP/minierp" "$DIR"
chmod +x "$DIR/bundle/minierp_app" "$DIR/runtime/node" "$DIR/minierp" 2>/dev/null || true
rm -f "$DIR/server/database/erp.db"

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
