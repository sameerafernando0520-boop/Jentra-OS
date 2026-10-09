import {createHash} from 'node:crypto';
export const projectId='xpdoufauvrbdmxgngetv';
export const id=label=>{const h=createHash('sha256').update('jentra-w5-runtime-review-20261008:'+label).digest('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`;};
export const accounts=['proposer','approver','executor','billing-admin','operator','foreign-member'].map(label=>({label,email:`w5-${label}@jentra.invalid`,
 authId:null,password:'new random 32-byte secret held only in the reviewed private credential store',mfa:'real Supabase TOTP enrollment, challenge and verification; no constructed AAL claims'}));
export const readPermissions=['analytics.view','workflow.process.view','crm.opportunities.view','finance.view','finance.receivables.view',
 'sales.returns.view','procurement.bills.view','people.view','people.payroll.view','projects.view','projects.cost.view','ai.proposals.view','analytics.reports.view'];
export const roles={
 reader:{requiresMfa:false,scope:'entity + RT1 branch',permissions:readPermissions},
 financeAnchor:{requiresMfa:false,scope:'entity; required by W3 statement/export parent checks',permissions:['finance.view','finance.reports.export']},
 proposer:{requiresMfa:false,scope:'entity + RT1 branch',permissions:['ai.proposals.manage','analytics.reports.manage','analytics.cash_dates.prepare','integrations.manage','finance.reports.export']},
 approver:{requiresMfa:true,scope:'entity + RT1 branch',permissions:['ai.proposals.approve','analytics.cash_dates.approve','finance.classifications.approve']},
 executor:{requiresMfa:true,scope:'entity + RT1 branch',permissions:['ai.proposals.execute']},
 billing:{requiresMfa:true,scope:'runtime + load-001 tenant only',permissions:['billing.read','billing.synthetic.manage','core.members.invite']},
 foreignReader:{requiresMfa:false,scope:'foreign entity + branch only',permissions:['analytics.view','workflow.process.view','crm.opportunities.view']},
 loadReader:{requiresMfa:false,scope:'load entity + branch only',permissions:['analytics.view','workflow.process.view','crm.opportunities.view']},
 loadBilling:{requiresMfa:false,scope:'load tenant only',permissions:['billing.read']},
};
// Proposer RPCs explicitly enforce MFA. Its integration delegation is AAL1 by
// installed contract, so that role cannot be globally marked requires_mfa.
export const assignments={proposer:['reader','financeAnchor','proposer'],approver:['reader','financeAnchor','approver'],
 executor:['reader','financeAnchor','executor'],'billing-admin':['billing'],'foreign-member':['foreignReader'],operator:[]};
export const plans=[
 {code:'w5_runtime_20261008',name:'Synthetic Wave 5 Runtime',trialDays:7,seats:5,entitlements:{analytics:true,'module.ai':true,'module.projects':true,'module.finance':true,'quota.ai.tokens':'8000','quota.webhook.deliveries':'100','quota.integration.commands':'200'}},
 {code:'w5_load_20261008',name:'Synthetic Wave 5 Load',trialDays:7,seats:4,entitlements:{analytics:true,'quota.ai.tokens':'0','quota.webhook.deliveries':'0','quota.integration.commands':'0'}},
 {code:'w5_quota10_20261008',name:'Synthetic Wave 5 Quota Contention',trialDays:7,seats:4,entitlements:{analytics:true,'quota.ai.tokens':'10','quota.webhook.deliveries':'10','quota.integration.commands':'10'}},
 {code:'w5_foreign_20261008',name:'Synthetic Wave 5 Foreign',trialDays:7,seats:1,entitlements:{analytics:true,'quota.ai.tokens':'0','quota.webhook.deliveries':'0','quota.integration.commands':'0'}},
];
export const scopes=Array.from({length:500},(_,i)=>{
 const key=i===0?'runtime':i===1?'foreign':`load-${String(i-1).padStart(3,'0')}`;
 return {key,tenantId:id(key+'.tenant'),entityId:id(key+'.entity'),branchId:id(key+'.branch1'),
  secondBranchId:i===0?id(key+'.branch2'):null,name:`Jentra Wave 5 ${key} Lab`,slug:`jentra-w5-${key}-20261008`,
  planCode:i===0?plans[0].code:i===1?plans[3].code:i===2?plans[2].code:plans[1].code};
});
export const migrationFiles=[
 '20260912153000_procurement_requisition_drafts.sql','20260913001000_procurement_requisition_workflow.sql',
 '20260913002000_procurement_reference_options.sql','20260913003000_procurement_sourcing.sql',
 '20260913004000_procurement_purchase_orders.sql','20260913005000_procurement_order_workflow.sql',
 '20260913006000_procurement_goods_receipts.sql','20260913007000_procurement_supplier_bills.sql',
 '20260914001000_procurement_supplier_settlement.sql','20260915001000_payable_allocation_corrections.sql',
 '20260925002000_wave3_financial_statements.sql','20260926009000_wave3_governed_report_exports.sql',
 '20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql',
 '20260928082234_wave4_attendance_intervals.sql','20260928083449_wave4_leave_ledger.sql',
 '20260930070000_wave4_synthetic_payroll.sql','20261001080000_wave4_projects_time.sql',
 '20261001100000_wave4_project_expenses_billing.sql','20261001110000_wave4_payroll_corrections.sql',
 '20261008090000_wave5_historical_pipeline.sql','20261008093000_wave5_persistent_delivery.sql',
 '20261008100000_wave5_invocation_storage.sql','20261008103000_wave5_dated_cash.sql',
 '20261008110000_wave5_governed_export_adapter.sql','20261008113000_wave5_statement_classifications.sql',
 '20261008120000_wave5_cash_payment_dates.sql','20261008123000_wave5_runtime_scope.sql',
];
export const workerConfig={projectId,url:`https://${projectId}.supabase.co`,runtimeId:id('worker-runtime'),
 hostBinding:{status:'awaiting owner supplied host/reverse proxy details',publicBaseUrl:null,listenAddress:'127.0.0.1',port:8785},
 receiver:{status:'awaiting owner supplied HTTPS receiver',url:null,allowedHosts:[],durableIdempotencyRequired:true},
 permittedScope:{tenantId:scopes[0].tenantId,legalEntityId:scopes[0].entityId,branchId:scopes[0].branchId},
 scopeExpiresAfterHours:24,schedulers:{deliveryIntervalMs:15000,deliveryBatchLimit:20,subscriptionIntervalMs:15000,subscriptionBatchLimit:50,healthIntervalMs:60000},
 http:{maxRequestBytes:65536,maxConcurrentRequests:8,reverseProxyTlsRequired:true,paths:['/v1/external/forecast','/v1/model/suggestion']},
 model:{approved:false,revision:1,provider:'openai.responses.v1',model:'gpt-4.1-mini-2025-04-14',maximumCalls:4,maxTokensPerInvocation:'2000',
  inputMaxBytes:65536,outputMaxBytes:8192,store:false,background:false,tools:[],numericProjection:'pipeline.current_weighted.v1',
  requests:['https://api.openai.com/v1/responses/input_tokens','https://api.openai.com/v1/responses']},
 secrets:{serviceKey:'W5_SUPABASE_SERVICE_ROLE_JWT',publishableKey:'W5_SUPABASE_PUBLISHABLE_KEY',modelKey:'W5_OPENAI_API_KEY',
  deliveryKeys:{'w5/runtime/20261008/delivery/v1':'W5_DELIVERY_KEY_V1','w5/runtime/20261008/delivery/v2':'W5_DELIVERY_KEY_V2'},
  externalCredential:'W5_EXTERNAL_CREDENTIAL',accountPasswords:'dedicated private OS credential store; six newly generated values'},
 external:{credentialId:id('external-credential'),subscriptionId:id('integration-subscription'),credentialExpiryHours:24,
  command:'analytics.freeze_pipeline.v1',schemaVersion:1,throttlePerMinute:60},
 operator:{actorLabel:'operator',active:true,healthRead:true,grantManage:true,tenantId:scopes[0].tenantId,
  authorityMinutes:45,grantMinutes:30,reason:'Owner-reviewed Wave 5 synthetic runtime health acceptance; isolated runtime tenant only'},
};
