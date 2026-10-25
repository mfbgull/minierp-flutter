from pathlib import Path
import json,sqlite3
root=Path(__file__).resolve().parents[2]
positive=root/'accounting-audit/evidence/backend-extension-run-OF2b8i'
risk=root/'accounting-audit/evidence/backend-count-risk-run-ZBybHv'
a=json.loads((positive/'results.json').read_text());b=json.loads((risk/'results.json').read_text())
assert a['completed'] and b['completed']
assert len(a['scenarios'])==3 and all(x['status']=='PASS' for x in a['scenarios'])
assert len(b['scenarios'])==2 and all(x['defectReproduced'] for x in b['scenarios'])
assert a['scenarios'][0]['actual']['produced']['1200']==130
assert a['scenarios'][0]['actual']['produced']['2200']==-30
assert a['scenarios'][0]['actual']['reversed']['1200']==100
assert a['scenarios'][1]['actual']['goods']['3300']==30
assert a['scenarios'][1]['actual']['cash']['3300']==80
assert a['scenarios'][1]['actual']['reversed']['3300']==0
assert a['scenarios'][2]['actual']['counted']['7200']==20
assert a['scenarios'][2]['actual']['corrected']['7200']==10
assert b['scenarios'][0]['actual']['status']==500
assert b['scenarios'][0]['actual']['batchValue']==40
assert b['scenarios'][1]['actual']['otherStock']==10
assert b['scenarios'][1]['actual']['otherCount']['counted_quantity']==8
for run in [positive,risk]:
 for scenario in json.loads((run/'results.json').read_text())['scenarios']:
  for name in scenario['artifacts']: assert (run/name).stat().st_size>0
 with sqlite3.connect((run/'erp.db').as_uri()+'?mode=ro',uri=True) as db:
  assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
  assert db.execute('PRAGMA foreign_key_check').fetchall()==[]
  assert db.execute('SELECT * FROM journal_entry_balances WHERE balance_cents!=0').fetchall()==[]
result={'status':'VERIFIED','positiveRun':str(positive.relative_to(root)),'riskRun':str(risk.relative_to(root)),'positiveScenarios':3,'reproducedCountDefects':2,'sqliteIntegrity':'ok','foreignKeyViolations':0,'unbalancedJournals':0}
(root/'accounting-audit/evidence/backend-extension-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
