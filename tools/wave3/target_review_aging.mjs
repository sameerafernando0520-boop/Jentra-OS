import assert from 'node:assert/strict';

const uuid = /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const decimal = value => {
  if (typeof value !== 'string' || !/^-?(0|[1-9]\d{0,13})(\.\d{1,6})?$/.test(value)) throw Error('Exact aging decimal string required');
  const negative=value.startsWith('-');const [whole,fraction='']=value.replace(/^-/,'').split('.');
  const micro=BigInt(whole)*1000000n+BigInt(fraction.padEnd(6,'0'));return negative?-micro:micro;
};
const text = micro => (micro<0n?'-':'')+(micro<0n?-micro:micro)/1000000n+'.'+String((micro<0n?-micro:micro)%1000000n).padStart(6,'0');
const day = value => {
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))throw Error('Exact aging ISO date required');
  const timestamp=Date.parse(value+'T00:00:00Z');
  if(!Number.isFinite(timestamp)||new Date(timestamp).toISOString().slice(0,10)!==value)throw Error('Exact aging ISO date required');
  return timestamp/86400000;
};
export const ordinaryReportMetrics=['trial_balance','aged_receivables','aged_payables','inventory_valuation','subledger_reconciliation'];
export const isAgedMetric = metric => metric==='aged_receivables'||metric==='aged_payables';
export function assertOrdinaryReportBinding(metric,call) {
  const p=call.params?.p_payload??call.payload;
  const expected={trial_balance:['generate_financial_statement','trial_balance'],
    aged_receivables:['generate_control_reconciliation_report','AR'],aged_payables:['generate_control_reconciliation_report','AP'],
    inventory_valuation:['generate_inventory_valuation_report',null],subledger_reconciliation:['generate_control_reconciliation_report',null]}[metric];
  if(!expected||call.rpc!==expected[0]||(expected[1]&&p?.kind!==expected[1]))throw Error('Ordinary-report metric must match its actual generation RPC and kind');
  if(isAgedMetric(metric)) {
    if(!p||!uuid.test(p.id??'')||Object.hasOwn(p,'party_id')||Object.hasOwn(p,'customer_id')||Object.hasOwn(p,'supplier_id'))throw Error('Entity-aged report must include all scoped parties');
    day(p.as_of);
    const a=call.aging;
    if(!a||!Number.isSafeInteger(a.item_count)||a.item_count<2||a.item_count>10000||!Number.isSafeInteger(a.party_count)||a.party_count<2||a.party_count>a.item_count||!Array.isArray(a.buckets)||!a.buckets.length)throw Error('Complete entity-aged count, multiple parties and exact bucket expectations required');
    let total=0;const seen=new Set();
    for(const b of a.buckets) {
      if(!/^[A-Z]{3}$/.test(b.currency_code??'')||!/^[A-Z]{3}$/.test(b.base_currency_code??'')||!Number.isInteger(b.bucket)||b.bucket< -1||b.bucket>4||!Number.isSafeInteger(b.item_count)||b.item_count<1)throw Error('Exact currency-separated aging bucket required');
      decimal(b.amount);decimal(b.base_amount);
      const key=b.currency_code+':'+b.base_currency_code+':'+b.bucket;if(seen.has(key))throw Error('Duplicate expected aging bucket');seen.add(key);total+=b.item_count;
    }
    if(total!==a.item_count)throw Error('Expected aging buckets omit scoped items');
  }
}
export function agedTotals(rows,asOf) {
  const cutoff=day(asOf),groups=new Map(),ids=new Set(),parties=new Set();
  if(!Array.isArray(rows)||rows.length>10000)throw Error('Bounded complete aged item population required');
  for(const r of rows) {
    if(!uuid.test(r.id??'')||ids.has(r.id)||!uuid.test(r.party_id??'')||!/^[A-Z]{3}$/.test(r.currency_code??'')||!/^[A-Z]{3}$/.test(r.base_currency_code??''))throw Error('Unique scoped aged item, party and currency required');
    ids.add(r.id);parties.add(r.party_id);
    if(day(r.posting_date)>cutoff)throw Error('Aged item exceeds the frozen posting cutoff');
    const due=day(r.due_date),original=decimal(r.original_amount),amount=decimal(r.open_amount),base=decimal(r.open_base_amount);
    const days=cutoff-due,bucket=original<0n?-1:days<=0?0:days<=30?1:days<=60?2:days<=90?3:4;
    const key=r.currency_code+':'+r.base_currency_code+':'+bucket;
    const g=groups.get(key)??{currency_code:r.currency_code,base_currency_code:r.base_currency_code,bucket,item_count:0,amount:0n,base_amount:0n};
    g.item_count++;g.amount+=amount;g.base_amount+=base;groups.set(key,g);
  }
  return {item_count:ids.size,party_count:parties.size,buckets:[...groups.values()].sort((a,b)=>(a.currency_code+':'+a.base_currency_code+':'+a.bucket).localeCompare(b.currency_code+':'+b.base_currency_code+':'+b.bucket)).map(g=>({...g,amount:text(g.amount),base_amount:text(g.base_amount)}))};
}
export async function collectAgedReport(call,summary,scope,request) {
  const p=call.params.p_payload;assertOrdinaryReportBinding(p.kind==='AR'?'aged_receivables':'aged_payables',call);
  const sameSummary=s => s&&s.id===p.id&&s.kind===p.kind&&s.as_of===p.as_of&&s.item_count===call.aging.item_count&&['tenant_id','legal_entity_id','branch_id'].every(k=>s[k]===scope[k]);
  if(!sameSummary(summary))throw Error('Aged report summary differs from the exact scope/cutoff/population');
  const rows=[];let offset=0,pages=0;
  while(true) {
    if(offset>=10000)throw Error('Aged report pagination exceeds the complete bounded population');
    const page=await request({rpc:'control_reconciliation_report_page',params:{p_tenant_id:scope.tenant_id,p_legal_entity_id:scope.legal_entity_id,p_branch_id:scope.branch_id,p_id:p.id,p_section:'items',p_after:offset,p_evidence_key:null}});
    pages++;
    if(!sameSummary(page.summary)||page.section!=='items'||page.evidence_key!==null||!Array.isArray(page.items)||page.items.length>50)throw Error('Foreign, stale or filtered aged report page');
    rows.push(...page.items);
    if(rows.length>call.aging.item_count)throw Error('Aged report population exceeds its exact expected count');
    if(page.next_cursor===null)break;
    if(page.items.length!==50||page.next_cursor!==String(offset+50))throw Error('Aged report cursor is missing, repeated or skips items');
    offset+=50;
  }
  const actual=agedTotals(rows,p.as_of);
  if(actual.item_count!==call.aging.item_count||actual.party_count!==call.aging.party_count)throw Error('Aged report is partial or its party population differs');
  const normalized=buckets=>buckets.map(b=>({...b,amount:text(decimal(b.amount)),base_amount:text(decimal(b.base_amount))})).sort((a,b)=>(a.currency_code+':'+a.base_currency_code+':'+a.bucket).localeCompare(b.currency_code+':'+b.base_currency_code+':'+b.bucket));
  assert.deepEqual(actual.buckets,normalized(call.aging.buckets),'Exact complete aged balances differ from approved expectations');
  return {...actual,source_read_count:pages};
}
