import {createEdgeRuntime} from '../../../workers/wave5/edge_runtime_20261013_r5.mjs';
// Same reviewed private schedule key, revocable external credential and caller
// JWT checks; the successor also recognizes Supabase's function-name namespace.
Deno.serve(createEdgeRuntime({env:Deno.env}));
