// Public, offline verification of saved synthetic statement responses.
// No network, credentials, accounting commands or acceptance decisions.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {FINANCE_ACCOUNTS,FINANCE_JOURNALS,FINANCE_SCOPE,FINANCE_ACTOR} from './finance_cash_fixture_20261013_r5.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const base='build/wave5-approved-execution-20261013-r5-a2/docs/verification/wave5/genuine-finance-finance-20261013-r5-1791894738890/';
const output='docs/verification/wave5/saved-statement-arithmetic-20261014-r5-a1';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const units=value=>{
 assert.match(value,/^-?\d+\.\d{6}$/);
 const negative=value.startsWith('-'), [whole,fraction]=value.replace(/^-/,'').split('.');
 const result=BigInt(whole)*1000000n+BigInt(fraction);return negative?-result:result;
};
const decimal=value=>`${value<0n?'-':''}${(value<0n?-value:value)/1000000n}.${((value<0n?-value:value)%1000000n).toString().padStart(6,'0')}`;
const bindings=[];
async function read(file){const bytes=await fs.readFile(path.join(root,file));bindings.push({path:file,bytes:bytes.length,sha256:hash(bytes)});return bytes;}
async function json(file){return JSON.parse(await read(file));}

function derive(asOf){
 const rows=new Map(FINANCE_ACCOUNTS.map(a=>[a.id,{...a,debit:0n,credit:0n}]));
 const included=FINANCE_JOURNALS.filter(j=>j.date<=asOf);
 for(const journal of included){
  assert.ok(journal.date>='2026-10-01','This saved fixture has no opening-period movement.');
  assert.ok(rows.has(journal.debit)&&rows.has(journal.credit));
  rows.get(journal.debit).debit+=units(journal.amount);
  rows.get(journal.credit).credit+=units(journal.amount);
 }
 const accounts=[...rows.values()].map(a=>({...a,signed:a.debit-a.credit}));
 const sum=fn=>accounts.reduce((n,a)=>n+fn(a),0n);
 const revenue=sum(a=>a.type==='revenue'?-a.signed:0n),expenses=sum(a=>a.type==='expense'?a.signed:0n);
 const assets=sum(a=>a.type==='asset'?a.signed:0n),liabilities=sum(a=>a.type==='liability'?-a.signed:0n);
 const equity=sum(a=>a.type==='equity'?-a.signed:0n),earnings=revenue-expenses;
 assert.equal(sum(a=>a.debit),sum(a=>a.credit));assert.equal(assets,liabilities+equity+earnings);
 return {accounts,included,summary:{account_count:accounts.length,journal_count:included.length*2,
  period_debit:decimal(sum(a=>a.debit)),period_credit:decimal(sum(a=>a.credit)),
  closing_debit:decimal(sum(a=>a.signed>0n?a.signed:0n)),closing_credit:decimal(sum(a=>a.signed<0n?-a.signed:0n)),difference:'0.000000'},
  amounts:{revenue,expenses,assets,liabilities,equity,earnings,
   inventory:sum(a=>a.label==='inventory'?a.signed:0n),costOfSales:sum(a=>a.label==='cost_of_sales'?a.signed:0n)}};
}

async function main(){
 assert.deepEqual(process.argv.slice(2),['--verify'],'Use only --verify; this writes new public evidence exclusively.');
 for(const suffix of ['.json','.md'])assert.equal(await fs.stat(path.join(root,output+suffix)).then(()=>true,()=>false),false,'Existing evidence must be preserved.');
 await read('tools/wave5/verify_saved_statement_arithmetic_20261014_r5.mjs');
 const fixture=await read('tools/wave5/finance_cash_fixture_20261013_r5.mjs');
 const snapshotFixture=await read('build/wave5-approved-execution-20261013-r5-a2/tools/wave5/finance_cash_fixture_20261013_r5.mjs');
 assert.equal(hash(fixture),hash(snapshotFixture),'Workspace fixture must equal the original execution fixture.');
 const original=await json(base+'00-source-before.json');
 assert.equal(original.administrativeSourceFixture,true);assert.equal(original.actualUserPosting,false);
 assert.equal(original.facts.journals,9);assert.equal(original.facts.lines,18);
 assert.deepEqual(original.facts.journalIds,FINANCE_JOURNALS.map(j=>j.id).sort());
 assert.equal(original.facts.sourceHash,'ff90ee8cb1e1a33982eedfc1d05a8b8118a463d8e2bd9a36ac9f1469eb40be38');
 const derived=derive('2026-10-13'),checks=[];
 const nullable=['revenue','expenses','net_profit','assets','liabilities','equity','current_earnings'];
 for(const kind of ['profit_loss','balance_sheet','trial_balance']){
  const report=await json(base+`statement-${kind}.json`),s=report.summary;
  assert.equal(report.actorId,FINANCE_ACTOR);assert.equal(report.sourceFixture,'administrative synthetic');
  assert.equal(s.id,report.id);assert.equal(s.kind,kind);assert.equal(s.as_of,'2026-10-13');
  assert.equal(s.tenant_id,FINANCE_SCOPE.tenantId);assert.equal(s.legal_entity_id,FINANCE_SCOPE.entityId);assert.equal(s.branch_id,FINANCE_SCOPE.branchId);
  assert.equal(s.base_currency_code,'LKR');assert.equal(s.period_start,'2026-10-01');assert.equal(s.period_end,'2026-10-31');
  assert.equal(s.comparative,null);assert.equal(s.comparative_period_id,null);assert.equal(s.version,1);assert.equal(s.status,'generated');
  assert.ok(Number.isFinite(Date.parse(s.generated_at)));assert.equal(new Date(s.generated_at).toISOString().slice(0,10),'2026-10-13');
  const expected={...derived.summary,...Object.fromEntries(nullable.map(k=>[k,null]))};
  if(kind==='profit_loss')Object.assign(expected,{revenue:decimal(derived.amounts.revenue),expenses:decimal(derived.amounts.expenses),net_profit:decimal(derived.amounts.earnings)});
  if(kind==='balance_sheet')Object.assign(expected,{assets:decimal(derived.amounts.assets),liabilities:decimal(derived.amounts.liabilities),equity:decimal(derived.amounts.equity),current_earnings:decimal(derived.amounts.earnings)});
  for(const [field,value] of Object.entries(expected)){assert.equal(s[field],value,`${kind}.${field}`);checks.push({kind,field,expected:value,actual:s[field],matched:true});}
 }
 const ratios=await json(base+'ratios-and-classification.json'),a=derived.amounts;
 const inputs={quick_ratio:[a.assets-a.inventory,a.liabilities],current_ratio:[a.assets,a.liabilities],assets_to_equity:[a.assets,a.equity+a.earnings],
  net_profit_margin:[a.earnings,a.revenue],gross_profit_margin:[a.revenue-a.costOfSales,a.revenue],liabilities_to_assets:[a.liabilities,a.assets]};
 const ratioChecks=[];
 for(const [name,[n,d]] of Object.entries(inputs)){
  assert.ok(n>=0n&&d>0n);const scaled=n*1000000n,q=scaled/d+((scaled%d)*2n>=d?1n:0n),actual=ratios.ratios.ratios[name];
  assert.equal(actual.numerator,decimal(n));assert.equal(actual.denominator,decimal(d));assert.equal(actual.exactValue,decimal(q));assert.equal(actual.unavailableReason,null);
  ratioChecks.push({name,numerator:decimal(n),denominator:decimal(d),exactValue:decimal(q),matched:true});
 }
 const nextDay=derive('2026-10-14'),bank=values=>values.accounts.find(a=>a.key==='bank').signed,payroll=values=>-values.accounts.find(a=>a.key==='payroll').signed;
 assert.equal(derived.included.length,8);assert.equal(nextDay.included.length,9);
 assert.equal(bank(nextDay)-bank(derived),3000000n);assert.equal(payroll(nextDay)-payroll(derived),3000000n);
 const ui=await read('apps/jentra_desktop/lib/src/features/financial_statements/financial_statement_screen.dart');
 assert.ok(ui.toString().includes("${report['journal_count']} journal lines"));
 assert.ok(ui.toString().includes("${summary['journal_count']} source lines"));
 for(const b of bindings)assert.equal(hash(await fs.readFile(path.join(root,b.path))),b.sha256,'Bound input changed during verification.');
 const evidence={kind:'offline-independent-saved-synthetic-statement-arithmetic-verification',verifiedAt:new Date().toISOString(),passed:true,
  projectId:'xpdoufauvrbdmxgngetv',savedStatementAsOf:'2026-10-13',inputBindings:bindings,arithmetic:'exact integer micro-units; no binary floating-point amounts',
  summaryFieldChecks:checks,summaryFieldCheckCount:checks.length,ratioChecks,ratioInputAndResultCheckCount:ratioChecks.length,
  cutoff:{fixtureJournals:9,includedJournals:8,sourceLines:16,excludedFutureJournal:FINANCE_JOURNALS.find(j=>j.key==='future-reversal').id,
   nextDayControlOnly:{date:'2026-10-14',includedJournals:9,bankIncrease:'3.000000',payrollLiabilityIncrease:'3.000000',actualNextDayReportQueried:false}},
  journalCountSemantics:'The stored journal_count is the source-line count. Existing UI explicitly labels it journal lines/source lines; 16 is correct for 8 two-line journals.',
  limitations:{source:'Reviewed administrative fixture amounts and saved genuine response summaries, not new live ledger rows.',
   canonicalFullStatementBodiesAvailable:false,fullCanonicalBodyReproduction:false,actualUserJournalPosting:false,operationalPayrollApproval:false,
   newLiveDatabaseVerification:false,newRequirementAcceptance:false,authenticatedNative:false,production:false,realBilling:false},
  actions:{networkCalls:0,liveSql:0,privateInputs:0,existingFilesChanged:0,SDKJobs:0}};
 const bytes=JSON.stringify(evidence,null,2)+'\n';await fs.writeFile(path.join(root,output+'.json'),bytes,{flag:'wx'});
 const markdown=`The three saved October 13 synthetic financial-statement summaries match independent exact arithmetic: ${checks.length} summary fields and all six ratio numerators, denominators and rounded results passed.\n\nThe calculation includes eight journals (16 source lines), excludes the future October 14 reversal, and retains all ten accounts. The reported journal_count is correctly displayed as source lines in the existing UI. The next-day control adds exactly LKR 3.000000 to cash and payroll liability; it is an offline control, not a newly queried report.\n\nThis verifies saved summaries against the preserved administrative fixture. Full frozen statement bodies, operational posting, current live behavior and requirement acceptance remain separate and unproved. No source amount, report, account, session or approval was changed.\n\n[Exact checks and input hashes](saved-statement-arithmetic-20261014-r5-a1.json).\n`;
 await fs.writeFile(path.join(root,output+'.md'),markdown,{flag:'wx'});
 process.stdout.write(JSON.stringify({passed:true,summaryFieldChecks:checks.length,ratioChecks:ratioChecks.length,evidence:{path:output+'.json',sha256:hash(bytes)},newPublicFiles:2,networkCalls:0,fullCanonicalBodyReproduction:false})+'\n');
}
main().catch(error=>{process.stderr.write(String(error.stack??error)+'\n');process.exitCode=1;});
