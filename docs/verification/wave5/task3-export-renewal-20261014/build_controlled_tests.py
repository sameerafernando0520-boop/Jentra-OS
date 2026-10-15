from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
original=ROOT/'docs/verification/wave5/task3-export-continuation-20261014/finance_exports_20261014_r5_a5.test.mjs'
s=original.read_text()
s=s[:s.index('async function publicPreparationInputs()')]
s=s.replace('EXPORTS_PROFILE,EXPORTS_DECISION,','EXPORTS_PROFILE,EXPORTS_A5_SOURCE_BINDINGS,EXPORTS_DEPENDENCY,EXPORTS_REVIEWED_BUDGET,EXPORTS_ORIGINAL_WINDOW,EXPORTS_OWNER_REPLY,EXPORTS_RUNTIME_ID,')
s=s.replace('EXPORTS_ROWS,EXPORTS_RUNTIME_EXPIRY,','EXPORTS_ROWS,validateExportsWindow,validateExportsTime,')
s=s.replace('EXPORTS_PLAN,EXPORTS_BUDGET_REVIEW_SHA,','EXPORTS_PLAN,')
s=s.replace('finance_exports_20261014_r5_a5','finance_exports_20261014_r5_a6').replace('task3-export-continuation-20261014','task3-export-renewal-20261014')
s=s.replace("const stamp='2026-10-14T07:00:00.000Z'", "const stamp='2026-10-14T14:00:00.000Z'")
s=s.replace("const writerId=", "const testWindow={notBefore:'2026-10-14T13:30:00.000Z',edgeExpiresAt:'2026-10-14T15:30:00.000Z',scopeExpiresAt:'2026-10-14T15:30:00.000Z',privateExpiresAt:'2026-10-14T15:00:00.000Z',expiresAt:'2026-10-14T15:00:00.000Z'};\nconst writerId=")
s=s.replace("expiresAt:'2026-10-14T09:00:00.000Z'",'window:testWindow')
s=s.replace('createExportsCallGate({now})','createExportsCallGate({now,window:testWindow})')
s=s.replace('startedAt:started})','startedAt:started,window:testWindow})')
s=s.replace('startedAt:started,expiresAt})','startedAt:started,window:{...testWindow,privateExpiresAt:expiresAt,expiresAt}})')
s=s.replace('132+ordinal+reserved','138+ordinal+reserved').replace('totalWorkflowRequestBound,156','totalWorkflowRequestBound,162')
s=s.replace("expiresAt:new Date(boundary==='authority'?end:now()+7200000).toISOString()", "window:{...testWindow,privateExpiresAt:new Date(boundary==='authority'?end:now()+3600000).toISOString(),expiresAt:new Date(boundary==='authority'?end:now()+3600000).toISOString()}")
s+=(OUT/'controlled_profile_and_window.tests.txt').read_text()
with (OUT/'finance_exports_20261014_r5_a6.test.mjs').open('x',encoding='utf8',newline='\n') as f:f.write(s)
