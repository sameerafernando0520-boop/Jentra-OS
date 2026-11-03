import {createEdgeRuntime} from '../../../workers/wave5/edge_runtime.mjs';
import {createRpcFailureDiagnosticFetch} from '../../../workers/wave5/rpc_failure_diagnostics.mjs';
import {freeAiConfiguration} from '../../../workers/wave5/free_ai_configuration.mjs';
// Scheduled calls use a scoped secret checked transactionally; external calls
// use revocable credentials; model reads use the requesting user's real JWT.
// There is no unauthenticated action or default background loop.
const fetchImpl=createRpcFailureDiagnosticFetch({url:freeAiConfiguration.url,
 emit:(event:unknown)=>console.error(JSON.stringify(event))});
Deno.serve(createEdgeRuntime({env:Deno.env,fetchImpl,reportFailure:(event:unknown)=>console.error(JSON.stringify(event))}));
