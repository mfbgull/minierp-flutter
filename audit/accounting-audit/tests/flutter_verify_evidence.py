"""Verify this workstream's evidence files without touching production data."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
evidence = root / 'accounting-audit/evidence'
names = [
    'flutter-inventory-run.log', 'flutter-inventory-run.exit', 'flutter-inventory-summary.json',
    'flutter-figures.csv', 'flutter-surfaces.csv', 'flutter-support.csv',
    'flutter-graph-discovery.json', 'flutter-graph-coverage.json',
    'flutter-report-regressions.log', 'flutter-report-regressions.exit',
    'flutter-balance-sheet-widget.json', 'flutter-balance-sheet.png', 'flutter-balance-sheet.csv',
    'flutter-csv-observation.json', 'flutter-salary-carryover-widget.json', 'flutter-payroll-api-fixture.json',
    'flutter-csv-regression.log', 'flutter-csv-regression.exit',
    'flutter-oracle-replay.log', 'flutter-oracle-replay.exit', 'flutter-oracle-models.json',
    'flutter-oracle-pnl-widget.json', 'flutter-oracle-balance-widget.json',
    'flutter-pnl-breakdown.log', 'flutter-pnl-breakdown.exit', 'flutter-pnl-breakdown.json',
    'flutter-harness-analyze.log', 'flutter-harness-analyze.exit',
]
paths = [evidence / name for name in names]
paths += [root / f'accounting-audit/findings/F-{n:03d}/finding.md' for n in range(40, 44)]
paths += [root / 'accounting-audit/workstreams/flutter-reports.md']
artifacts = []
for path in paths:
    data = path.read_bytes()
    assert data, f'Empty evidence: {path}'
    artifacts.append({'path': str(path.relative_to(root)), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})

for name, expected in [('flutter-inventory-run', '0'), ('flutter-report-regressions', '1'), ('flutter-csv-regression', '1'), ('flutter-oracle-replay', '0'), ('flutter-pnl-breakdown', '1'), ('flutter-harness-analyze', '0')]:
    assert (evidence / f'{name}.exit').read_text().strip() == expected, name
assert '+3: All tests passed!' in (evidence / 'flutter-oracle-replay.log').read_text()
assert 'No issues found!' in (evidence / 'flutter-harness-analyze.log').read_text()
csv_log = (evidence / 'flutter-csv-regression.log').read_text()
assert "Actual: ['Cash', '', 'Rs. 1', '000.00']" in csv_log
assert 'LocaleDataException' not in csv_log and 'Compilation failed' not in csv_log
model = json.loads((evidence / 'flutter-oracle-models.json').read_text())
assert model['expected'] == model['actual']
assert len(model['actual']) == 15
payroll = json.loads((evidence / 'flutter-salary-carryover-widget.json').read_text())
assert payroll['expected_remaining'] == 800 and payroll['actual_remaining_from_client_expression'] == 600
assert any('Remaining Balance: Rs. 600.00' in text for text in payroll['visible_text'])
csv = json.loads((evidence / 'flutter-csv-observation.json').read_text())
assert csv['actual_columns'] == 4 and csv['expected_columns'] == 3
pnl = json.loads((evidence / 'flutter-pnl-breakdown.json').read_text())
assert pnl['expected_breakdown_total'] == 20 and pnl['actual_breakdown_total'] == 10 and pnl['profit_is_correct']
output = root / '.omo/evidence/flutter-reports/verification.json'
output.write_text(json.dumps({'checks_passed': True, 'artifact_count': len(artifacts), 'artifacts': artifacts}, indent=2))
print(f'PASS: {len(artifacts)} nonempty artifacts verified; expected exit codes and numerical observables matched. {output}')
