from pathlib import Path
import hashlib

ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
def replace(text,old,new,count=1):
    assert text.count(old)==count,(old[:100],text.count(old),count)
    return text.replace(old,new)
def exclusive(path,text):
    with path.open('x',encoding='utf-8',newline='\n') as handle: handle.write(text)

original=ROOT/'tools/wave5/finance_exports_20261014_r5_a5.mjs'
assert hashlib.sha256(original.read_bytes()).hexdigest()=='ab9ec8c1a97a0a009081e5aba58db1359fd6d5df3a3d0ce2680bf4c43f50a544'
s=original.read_text()
s=s.replace('finance_exports_20261014_r5_a5','finance_exports_20261014_r5_a6').replace('finance-exports-preparation-20261014-r5-a5','finance-exports-preparation-20261014-r5-a6').replace('finance-exports-once-20261014-r5-a5','finance-exports-once-20261014-r5-a6').replace('genuine-finance-exports-20261014-r5-a5','genuine-finance-exports-20261014-r5-a6').replace('task3-export-continuation-20261014/finance_exports_','task3-export-renewal-20261014/finance_exports_')
start=s.index('export const EXPORTS_PROFILE=')
end=s.index("const a3=",start)
s=s[:start]+'''// These are FUTURE public integration records. Source preparation creates none.
export const EXPORTS_PROFILE=base+'task3-export-renewal-20261014/execution-profile-a1.json';
export const EXPORTS_FINAL_REVIEW=base+'task3-export-renewal-20261014/final-operation-review-a1.json';
export const EXPORTS_PROFILE_PATHS=Object.freeze({
 sourcePolicy:base+'task3-export-renewal-20261014/source-policy-a1.json',
 independentReview:base+'task3-export-renewal-20261014/independent-policy-review-a1.json',
 ownerDecision:base+'runtime-renewal-export-owner-decision-20261014-r5-a1.json',
 renewalReadback:base+'runtime-renewal-two-row-readback-20261014-r5-a1.json',
 metadata:base+'private-owner-input-ready-20261014-r5-a10.json',
 refresh:base+'private-owner-scope-refresh-20261014-r5-a10.json',
 accounting:base+'finance-cumulative-read-accounting-20261014-r5-a7.json',
 dependency:base+'runtime-expiry-dependency-readonly-20261014-r5-a1.json'
});
export const EXPORTS_DEPENDENCY=Object.freeze({path:EXPORTS_PROFILE_PATHS.dependency,
 sha256:'0dc87893b6635d3ef4fb64c724e6aab2a42dd89d9d07ffc42251105f7c3141dc'});
export const EXPORTS_A5_SOURCE_BINDINGS=immutableJson([
 {path:'tools/wave5/finance_exports_20261014_r5_a5.mjs',sha256:'ab9ec8c1a97a0a009081e5aba58db1359fd6d5df3a3d0ce2680bf4c43f50a544'},
 {path:'tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs',sha256:'030c44b84a8c5073c6c2157352fd70783c232ee256befda6ec28e9b6a723cd32'},
 {path:base+'task3-export-continuation-20261014/finance_exports_20261014_r5_a5.test.mjs',sha256:'fedd5d9c86d767508bc9e214225316f457ac3b24dce1e1359a581448c998a351'}
]);
export const EXPORTS_RUNTIME_ID='778237e3-3d4e-4871-8cc9-e08b07b989c7';
export const EXPORTS_ORIGINAL_WINDOW=immutableJson({
 scopeIssuedAt:'2026-10-13T08:13:04.144135+00:00',scopeExpiresAt:'2026-10-14T08:13:04.144135+00:00',
 scopeNonWindowHash:'3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387',
 edgeIssuedAt:'2026-10-13T09:57:07.481942+00:00',edgeExpiresAt:'2026-10-14T09:57:07.481942+00:00',
 edgeNonWindowHash:'77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139'
});
export const EXPORTS_OWNER_REPLY='Approve the exact two-row runtime renewal and export a6 continuation';
export const EXPORTS_MAX_WINDOW_MS=7200000;
export const EXPORTS_REVIEWED_BUDGET=immutableJson({recordedPrior:134,ownerRefreshCalls:1,renewalControlCalls:3,prior:138,ordinary:24,ordinaryLimit:162,resolution:1,total:163});
''' +s[end:]
s=replace(s,"export const EXPORTS_RUNTIME_EXPIRY='2026-10-14T09:57:07.481942Z';\nexport const EXPORTS_DAY='2026-10-14';\nexport const EXPORTS_PRIOR=132;\nexport const EXPORTS_LIMIT=157;", "export const EXPORTS_PRIOR=138;\nexport const EXPORTS_LIMIT=163;")
start=s.index('export function validateExportsTime(')
end=s.index('export function validateExportsConsumed(',start)
s=s[:start]+(OUT/'window_and_profile.source.txt').read_text()+s[end:]
# Preserve the a5 algorithm and transport behavior, forwarding the explicit
# immutable window through every gate rather than retaining any old default.
s=s.replace('expiresAt=EXPORTS_RUNTIME_EXPIRY','window')
s=s.replace('server:true,expiresAt','server:true,window')
s=s.replace('now:now(),expiresAt','now:now(),window')
s=s.replace('now,startedAt,signal,expiresAt','now,startedAt,signal,window')
s=s.replace('{expiresAt}', '{window}')
s=s.replace('Date.parse(expiresAt),Date.parse(EXPORTS_RUNTIME_EXPIRY)', 'utcMillis(window.expiresAt)')
s=s.replace('Date.parse(expiresAt)', 'utcMillis(window.expiresAt)')
# Only remaining a5 runtime budget values are changed, never its files.
for old,new in [('priorConservativeBound:132','priorConservativeBound:138'),('132+ordinary+resolutions','138+ordinary+resolutions'),('maximumCumulativeAttemptLimit:157','maximumCumulativeAttemptLimit:163'),('<=157','<=163'),('EXPORT_CUMULATIVE157','EXPORT_CUMULATIVE163')]: s=s.replace(old,new)
s=replace(s,"must(typeof now==='function'&&Number.isFinite(startedAt),'EXPORT_ATTEMPT_GATE_REQUIRED');", "must(typeof now==='function'&&Number.isFinite(startedAt),'EXPORT_ATTEMPT_GATE_REQUIRED');\n window=immutableJson(validateExportsWindow(window));validateExportsTime(startedAt,{window});")
s=replace(s," 'BOUND_EXPORT_EXECUTION_PORTS_REQUIRED');\n const gate=", " 'BOUND_EXPORT_EXECUTION_PORTS_REQUIRED');\n window=immutableJson(validateExportsWindow(window));\n const gate=")
s=replace(s,"const remaining=evidenceOnly?Math.min(maxMs,5000):", "if(!evidenceOnly){try{validateExportsTime(now(),{window});}catch(error){finish(reject,error);return;}}\n  const remaining=evidenceOnly?Math.min(maxMs,5000):")
s=replace(s,"validateExportsTime(body.p_client_timestamp,{window});validateExportsTime(body.p_payload.prepared_at,{window});", "validateExportsTime(body.p_client_timestamp,{now,window});validateExportsTime(body.p_payload.prepared_at,{now,window});")
start=s.index('export function validateExportsPreparation(')
end=s.index('export async function writeExportsEvidence(',start)
s=s[:start]+(OUT/'preparation_and_review.source.txt').read_text()+s[end:]
s=s.replace('expiresAt:verified.plan.authorizationExpiresAt','window:verified.plan.window')
s=s.replace('Date.parse(verified.plan.authorizationExpiresAt)','utcMillis(verified.plan.window.expiresAt)')
s=s.replace('priorConservativeBound:138,cumulativeLimit:157','priorConservativeBound:138,cumulativeLimit:163')
s=replace(s,"key=runtimeSealKey(config.encryptionKey);", "must(sameFinanceJson(config.exportWindow,verified.plan.window),'EXACT_PRIVATE_ADAPTER_WINDOW_REQUIRED');key=runtimeSealKey(config.encryptionKey);")
# Close the source-verification-to-stdin gap after waiting for a private input.
s=replace(s,"const executionStartedAt=Date.now();validateExportsTime(executionStartedAt,{window:verified.plan.window});", "const reverified=await verifyExportsPreparation();\n  must(reverified.planSha256===verified.planSha256,'EXPORT_PUBLIC_INPUT_CHANGED_BEFORE_UNSEAL');\n  await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,{path:EXPORTS_FINAL_REVIEW,sha256:process.argv[3]});\n  await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,{path:verified.plan.privateAdapterPredecessor.path,sha256:finalReview.privateAdapter.afterSha256});\n  const executionStartedAt=Date.now();validateExportsTime(executionStartedAt,{window:verified.plan.window});")
exclusive(ROOT/'tools/wave5/finance_exports_20261014_r5_a6.mjs',s)

p=(ROOT/'tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs').read_text().replace('finance_exports_20261014_r5_a5','finance_exports_20261014_r5_a6')
p=p.replace('EXPORTS_RUNTIME_EXPIRY,\n EXPORTS_DAY,','EXPORTS_A5_SOURCE_BINDINGS,\n ')
p=p.replace('...Object.values(EXPORTS_PRESERVED_BINDINGS)', '...EXPORTS_A5_SOURCE_BINDINGS,...Object.values(EXPORTS_PRESERVED_BINDINGS)')
p=p.replace("kind:'source-bound-genuine-export-only-preparation'","kind:'source-bound-renewed-export-a6-preparation'")
p=p.replace('priorConservativeBound:132','priorConservativeBound:138').replace('ordinaryLimit:156','ordinaryLimit:162').replace('cumulativeLimit:157','cumulativeLimit:163')
p=replace(p,"explicitAdditionalCeiling:7,requiredActualExportUtcDay:EXPORTS_DAY,originalFixtureUtcDay:FINANCE_CALENDAR.fixtureDay,\n  authorizationExpiresAt:profile.authorizationExpiresAt,runtimeAuthorityExpiresAt:EXPORTS_RUNTIME_EXPIRY,profileBinding,controlBindings:profile.controlBindings,", "explicitAdditionalCeiling:13,originalFixtureUtcDay:FINANCE_CALENDAR.fixtureDay,window:profile.window,\n  profileBinding,controlBindings:profile.controlBindings,")
p=replace(p,"const now=Date.parse(preparedAt);validateExportsProfile(profile,documents,now);", "const now=Date.parse(preparedAt);validateExportsProfile(profile,documents,now);\n must(oldPlan?.sourceBindings?.length===68,'EXACT_68_PRESERVED_ORIGINAL_BINDINGS_REQUIRED');\n must(documents.sourcePolicy.exportSourceBindings.every(row=>sourceBindings.some(actual=>actual.path===row.path&&actual.sha256===row.sha256)),\n  'EXACT_INDEPENDENTLY_REVIEWED_A6_SOURCES_REQUIRED');")
exclusive(ROOT/'tools/wave5/prepare_finance_exports_20261014_r5_a6.mjs',p)
