#!/usr/bin/env bash
# Run every gate CI runs (.github/workflows/ci.yml), in one command.
#
# The commands below are deliberately byte-identical to CI's. When you change
# one, change both — a local check that passes while CI fails is worse than no
# check, because it teaches you to ignore the result.
#
# Usage:
#   scripts/check.sh           # everything (lint/typecheck/analyze are fast;
#                              # the two suites take ~10 min each)
#   scripts/check.sh --quick   # skip the two full test suites
#   scripts/check.sh --server  # server gates only
#   scripts/check.sh --flutter # flutter gates only
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUICK=0
RUN_SERVER=1
RUN_FLUTTER=1

for arg in "$@"; do
  case "$arg" in
    --quick)   QUICK=1 ;;
    --server)  RUN_FLUTTER=0 ;;
    --flutter) RUN_SERVER=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

FAILED=()

step() {
  local name="$1"; shift
  echo ""
  echo "── $name"
  if "$@"; then
    echo "   ok"
  else
    echo "   FAILED: $name"
    FAILED+=("$name")
  fi
}

if [[ $RUN_SERVER -eq 1 ]]; then
  step "server: typecheck"  bash -c "cd '$ROOT/server' && npm run typecheck"
  step "server: lint"       bash -c "cd '$ROOT/server' && npm run lint"
  if [[ $QUICK -eq 0 ]]; then
    step "server: test"     bash -c "cd '$ROOT/server' && npm test -- --silent"
  fi
fi

if [[ $RUN_FLUTTER -eq 1 ]]; then
  step "flutter: analyze"   bash -c "cd '$ROOT' && flutter analyze"
  step "flutter: l10n drift" bash -c "cd '$ROOT' && node scripts/l10n-drift.js"
  if [[ $QUICK -eq 0 ]]; then
    step "flutter: test"    bash -c "cd '$ROOT' && flutter test --reporter compact"
  fi
fi

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "all checks passed"
