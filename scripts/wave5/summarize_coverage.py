"""Merge genuine source-matched Wave 5 coverage; preserve per-gate provenance."""
from pathlib import Path
import hashlib
import json

ROOT=Path(__file__).resolve().parents[2]
SNAPSHOT=Path('C:/jw4-wave5-20261006')
EVIDENCE=ROOT/'docs/verification/wave5'
MANIFEST=EVIDENCE/'client-snapshot-build-final-20261006.json'
PAIRS=[('domain','packages/jentra_domain','coverage/wave5-final-checked/lcov.info'),
       ('platform','packages/jentra_platform','coverage/lcov.info'),
       ('desktop','apps/jentra_desktop','coverage/lcov.info')]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    manifest=json.loads(MANIFEST.read_text(encoding='utf-8'))
    if not manifest['source_stable']:raise ValueError('Unstable source capture')
    records={};inputs=[]
    for gate,base,name in PAIRS:
        raw=SNAPSHOT/base/name
        saved=EVIDENCE/f'{gate}-final-branch-20261006.lcov'
        saved.write_bytes(raw.read_bytes());inputs.append({'gate':gate,'path':saved.relative_to(ROOT).as_posix(),'sha256':sha(saved)})
        for block in raw.read_text(encoding='utf-8').split('end_of_record'):
            rows=block.splitlines();sf=next((r[3:] for r in rows if r.startswith('SF:')),None)
            if not sf:continue
            path=Path(sf) if Path(sf).is_absolute() else (SNAPSHOT/base/sf).resolve()
            if not path.is_relative_to(SNAPSHOT):continue
            rel=path.relative_to(SNAPSHOT).as_posix()
            if '/lib/src/analytics/' not in rel:continue
            expected=manifest['source_hashes'].get(rel)
            if not expected or sha(path)!=expected or sha(ROOT/rel)!=expected:raise ValueError(f'Stale coverage source: {rel}')
            record=records.setdefault(rel,{'sha256':expected,'lines':{},'branches':{},'gates':[]});record['gates'].append(gate)
            for row in rows:
                if row.startswith('DA:'):
                    line,count=row[3:].split(',')[:2];record['lines'][line]=max(record['lines'].get(line,0),int(count))
                elif row.startswith('BRDA:'):
                    line,block_id,branch,count=row[5:].split(',');key=f'{line}:{block_id}:{branch}'
                    record['branches'][key]=max(record['branches'].get(key,0),0 if count=='-' else int(count))
    output=[]
    for name,r in sorted(records.items()):
        line_count=len(r['lines']);branch_count=len(r['branches']);line_hit=sum(v>0 for v in r['lines'].values());branch_hit=sum(v>0 for v in r['branches'].values())
        output.append({'path':name,'sha256':r['sha256'],'gates':r['gates'],'line_count':line_count,'line_hit':line_hit,
            'line_percent':round(100*line_hit/line_count,2) if line_count else None,'branch_count':branch_count,'branch_hit':branch_hit,
            'branch_percent':round(100*branch_hit/branch_count,2) if branch_count else None})
    domain=[r for r in output if r['path'].startswith('packages/jentra_domain/')]
    report={'scope':'Changed Wave 5 analytics files only; no full-wave acceptance inferred','inputs':inputs,'manifest_sha256':sha(MANIFEST),
            'source_match':True,'files':output,'critical_domain_branches_at_least_90':all(r['branch_percent'] is not None and r['branch_percent']>=90 for r in domain)}
    (EVIDENCE/'coverage-final-20261006.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'source_match':True,'critical_domain_branches_at_least_90':report['critical_domain_branches_at_least_90'],'domain':domain}))
if __name__=='__main__':main()
