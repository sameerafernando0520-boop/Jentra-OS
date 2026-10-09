import {createEdgeRuntime} from '../../../workers/wave5/edge_runtime.mjs';
// Scheduled calls use a scoped secret checked transactionally; external calls
// use revocable credentials; model reads use the requesting user's real JWT.
// There is no unauthenticated action or default background loop.
Deno.serve(createEdgeRuntime({env:Deno.env}));
