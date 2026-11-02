from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[2]
files=set()
for scope in ['models','services','controllers','routes','migrations','boot','config','middleware','utils','types']:
 files.update(p for p in (root/'server/src'/scope).rglob('*') if p.suffix in ['.ts','.sql'] and '__tests__' not in str(p))
files.add(root/'server/src/app.ts')
out=[]
for p in sorted(files):
 s=p.read_text();lines=s.splitlines()
 out.append({'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'lines':len(lines),'imports':re.findall(r"from ['\"]([^'\"]+)",s),'accounting_calls':[{'line':i+1,'text':l.strip()} for i,l in enumerate(lines) if re.search(r'AccountingService\.|postEntry\(|voidJournal|assertPeriod|transaction\(|requirePermission\(',l)],'money_columns':[{'line':i+1,'text':l.strip()} for i,l in enumerate(lines) if re.search(r'CREATE TABLE|CREATE TRIGGER|CHECK\s*\(|REFERENCES|CREATE.*INDEX',l)]})
(root/'accounting-audit/evidence/backend-source-inventory.json').write_text(json.dumps(out,indent=2))
print(json.dumps({'files':len(out),'scopes':['models','services','controllers','routes','migrations','boot','config','middleware','utils','types','app.ts'],'artifact':'accounting-audit/evidence/backend-source-inventory.json'}))
