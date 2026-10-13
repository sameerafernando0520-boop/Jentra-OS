import test from 'node:test';
import assert from 'node:assert/strict';
import {validateSourceRead,validateForecastRead} from './source_workflow_management_20261013_r5.mjs';
const scope={tenantId:'tenant',entityId:'entity',branchId:'branch'};
test('empty, foreign and wrong scoped source projections cannot pass as nonempty',()=>{
 assert.throws(()=>validateSourceRead({source:{complete:true,sourceCount:0},observations:[]},scope));
 assert.throws(()=>validateSourceRead({source:{complete:true,sourceCount:4,tenantId:'foreign'},observations:[]},scope));
 assert.throws(()=>validateForecastRead({id:'invented',canonicalText:'{}',sourceHash:'invented',evidence:{sourceCount:2}},scope));
});
test('imprecise, unbalanced process numerics and duplicated event identities are rejected',()=>{
 const source={complete:true,sourceCount:4,...scope};
 const observations=Array.from({length:4},(_,i)=>({...scope,id:'event-'+i,activeMinutes:'30.000000',waitMinutes:'10.000000',completedAt:i%2?'date':null}));
 assert.throws(()=>validateSourceRead({source,observations},scope));
 assert.throws(()=>validateSourceRead({source,observations:observations.map(o=>({...o,id:'same'}))},scope));
});
