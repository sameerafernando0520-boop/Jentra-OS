import {createEdgeReceiver} from '../../../workers/wave5/edge_receiver_20261013_r5.mjs';
// Same exact-byte HMAC, source, scope and live subscription checks.
Deno.serve(createEdgeReceiver({env:Deno.env}));
