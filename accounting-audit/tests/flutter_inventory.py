"""Audit-only inventory. Run from repository root; production files are read-only.

Exhaustive *lexical* enumeration is not exhaustive semantic verification. Rows are
deliberately NOT TESTED until a scenario verifies their actual financial result.
"""
import csv
import hashlib
import json
import posixpath
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'accounting-audit/evidence'
FILES = sorted(p for p in subprocess.check_output(
    ['rg', '--files', 'lib'], cwd=ROOT, text=True).splitlines() if p.endswith('.dart'))
SOURCES = {p: (ROOT / p).read_text() for p in FILES}
money = re.compile(r'currency|formatAsCurrency|formatAsFixed|toStringAsFixed|PlutoColumnType\.number|\b(?:amount|balance|debit|credit|total|profit|cost|price|tax|discount|salary|wage|revenue|margin|outstanding|payable|receivable|refund|overhead|inflow|outflow|principal|installment|valuation|payment|paid|loan|capital|withdrawal|earnings|netIncome|grossProfit|cogs|quantity|qty|stockValue)\w*', re.I)
definition = re.compile(r'^\s*(?:final |static |const |num |double |int |String |class |Future|Map|List)')
providers = re.compile(r'ref\.(?:watch|read)\(\s*(\w+Provider)')
invalidations = re.compile(r'(?:ref\.)?invalidate\(\s*(\w+)')
imports = re.compile(r"import ['\"]([^'\"]+)['\"]")
endpoint_constants = dict(re.findall(r"static const (\w+) = '([^']+)';", SOURCES['lib/core/api/endpoints.dart']))

def dependencies(path, depth=3, visited=None):
    visited = set() if visited is None else visited
    if path in visited or depth < 0 or path not in SOURCES:
        return visited
    visited.add(path)
    for imp in imports.findall(SOURCES[path]):
        if imp.startswith('package:minierp_app/'):
            child = 'lib/' + imp.removeprefix('package:minierp_app/')
        elif not imp.startswith(('package:', 'dart:')):
            child = posixpath.normpath(posixpath.join(posixpath.dirname(path), imp))
        else:
            continue
        dependencies(child, depth - 1, visited)
    return visited

def csv_write(name, rows, fields):
    with (OUT / name).open('w', newline='') as out:
        writer = csv.DictWriter(out, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

rows = []
screens = []
support = []
for path, content in SOURCES.items():
    if path.startswith('lib/l10n/'):
        continue
    lines = content.splitlines()
    dep_paths = dependencies(path)
    watched = sorted(set(providers.findall(content)))
    refresh = sorted(set(invalidations.findall(content)))
    repos = sorted(p for p in dep_paths if 'repository' in p)
    endpoints = sorted({endpoint_constants[c] for p in dep_paths for c in re.findall(r'Endpoints\.(\w+)', SOURCES[p]) if c in endpoint_constants})
    hits = []
    for i, line in enumerate(lines):
        if line.lstrip().startswith(('//', '///', '*')) or not money.search(line):
            continue
        if path.startswith(('lib/features/', 'lib/widgets/')) or path in ['lib/core/utils/csv_export.dart', 'lib/core/utils/csv_order_builders.dart', 'lib/core/utils/ledger_export.dart']:
            hits.append(i + 1)
            formatter = 'currency settings-backed; default PKR/en 2dp' if 'currency(' in line or 'formatAsCurrency' in line else ('toStringAsFixed precision shown in expression' if 'toStringAsFixed' in line else ('Pluto numeric format shown in expression' if 'PlutoColumnType.number' in line else 'see expression and caller; NOT TESTED'))
            kind = 'print/export' if re.search(r'pdf|export|csv', path) else ('local preview/calculation' if re.search(r'calculations|form|line_calc|salary_pay', path) else 'display/model/provider candidate')
            rows.append({
                'id': f'FIG-{len(rows)+1:05}', 'source': path, 'line': i+1,
                'surface': path.split('/')[2] if path.startswith('lib/features/') else 'shared',
                'figure_expression': line.strip(), 'context': ' | '.join(s.strip() for s in lines[max(0,i-2):i+3]),
                'source_kind': kind, 'providers_in_file': ';'.join(watched),
                'candidate_repositories_depth3': ';'.join(repos),
                'candidate_endpoints_depth3': ';'.join(endpoints),
                'refresh_in_file': ';'.join(refresh) or 'none in this file; parent/module refresh may apply',
                'rounding': formatter, 'sign_and_label': 'expression/context; not independently verified',
                'status': 'NOT TESTED', 'evidence': 'lexical source inventory only',
            })
    if hits:
        screens.append({'source': path, 'candidate_count': len(hits), 'providers': ';'.join(watched), 'repositories': ';'.join(repos), 'refresh': ';'.join(refresh), 'status': 'NOT TESTED', 'sha256': hashlib.sha256(content.encode()).hexdigest()})
    if any(x in path for x in ('repository','providers','models','calculations','pdf','export')):
        for i,line in enumerate(lines):
            if money.search(line) and not line.lstrip().startswith('//'):
                support.append({'source':path,'line':i+1,'expression':line.strip(),'status':'NOT TESTED'})

csv_write('flutter-figures.csv', rows, list(rows[0]))
csv_write('flutter-surfaces.csv', screens, list(screens[0]))
csv_write('flutter-support.csv', support, list(support[0]))
counts = {
    'dart_files_scanned': len(FILES), 'candidate_source_surfaces': len(screens),
    'candidate_financial_numeric_lines': len(rows), 'support_lines': len(support),
    'definition': 'All non-comment matching lines in production Dart features/widgets and CSV/export utilities; includes control/data definitions and nonmonetary stock quantities to avoid excluding potential financial dependencies.',
    'limits': 'Regex inventory, not AST data flow. Nested/imported callbacks can resolve beyond depth 3. Candidate endpoints are dependency sets, not proven per-line sources. Status requires manual report matrix and executed scenario override; this inventory is not a blanket PASS.',
    'uncompiled_fragments': ['lib/features/owner_equity/owner_capital_tab.dart.part1','lib/features/owner_equity/owner_capital_tab.dart.part2'],
}
(OUT/'flutter-inventory-summary.json').write_text(json.dumps(counts,indent=2))
print(json.dumps(counts,indent=2))
