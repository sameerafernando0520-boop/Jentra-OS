// Additional native cash-date dependencies, prepared for review only.
// Keep the earlier unbound review's source plan and SQL unchanged.
import * as earlier from './runtime_plan.mjs';
export const {accounts,assignments,id,projectId,scopes,workerConfig}=earlier;
export const roles=structuredClone(earlier.roles);
roles.proposer.permissions.push('people.payroll.settle','projects.expenses.settle');
roles.approver.permissions.push('people.payroll.approve','people.payroll.correction.approve','projects.expenses.approve');
export const plans=structuredClone(earlier.plans);
plans.find(p=>p.code==='w5_runtime_20261008').entitlements['module.people']=true;
