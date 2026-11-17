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

# Report (never fail) the finding-tagged tests: server `it.failing`/`it.skip`
# and Flutter `skip: true` with a RED-BY-DESIGN marker. These are known,
# unfixed findings kept green on purpose — the count keeps them visible so
# nobody forgets they are parked. See audit/FINDINGS-STATUS.md.
report_finding_tagged() {
  local server_failing server_skipped flutter_skipped
  server_failing=$(grep -rEo "it\.failing\(" "$ROOT/server/src/__tests__" 2>/dev/null | wc -l | tr -d ' ')
  server_skipped=$(grep -rEo "it\.skip\(" "$ROOT/server/src/__tests__" 2>/dev/null | wc -l | tr -d ' ')
  flutter_skipped=$(grep -rl "RED-BY-DESIGN" "$ROOT/test" 2>/dev/null | wc -l | tr -d ' ')
  echo "   finding-tagged tests: server it.failing=$server_failing it.skip=$server_skipped, flutter RED-BY-DESIGN files=$flutter_skipped"
  if [[ "$server_failing" -gt 0 || "$server_skipped" -gt 0 || "$flutter_skipped" -gt 0 ]]; then
    echo "   (parked findings — see audit/FINDINGS-STATUS.md; remove the tag when fixed)"
  fi
}

if [[ $RUN_SERVER -eq 1 ]]; then
  step "server: typecheck"  bash -c "cd '$ROOT/server' && npm run typecheck"
  step "server: lint"       bash -c "cd '$ROOT/server' && npm run lint"
  if [[ $QUICK -eq 0 ]]; then
    # Coverage first: fallow's health/CRAP metrics need measured Istanbul
    # coverage (CI's fallow job does the same), and the audit aborts
    # without it.
    step "server: test"     bash -c "cd '$ROOT/server' && npm test -- --silent --coverage"
  fi
  # Same command CI runs: locally the tree is compared against HEAD, in CI
  # against the push/PR base. The version is pinned because the baselines in
  # audit/fallow-baselines/ are only comparable against the analyzer that
  # produced them. Note: in --quick mode the audit consumes whatever
  # coverage file is already on disk — CI or a previous full run — so its
  # health results are only as fresh as that file.
  step "server: fallow"     bash -c "cd '$ROOT' && npx --yes fallow@3.34.1 audit --base HEAD"
fi

if [[ $RUN_FLUTTER -eq 1 ]]; then
  step "flutter: analyze"   bash -c "cd '$ROOT' && flutter analyze"
  step "flutter: l10n drift" bash -c "cd '$ROOT' && node scripts/l10n-drift.js"
  if [[ $QUICK -eq 0 ]]; then
    step "flutter: test"    bash -c "cd '$ROOT' && flutter test --reporter compact"
  fi
fi

echo ""
echo "── finding-tagged tests"
report_finding_tagged

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "all checks passed"
