import {createEdgeReceiver} from '../../../workers/wave5/edge_receiver.mjs';
// Custom HMAC authentication is required before any receipt/fault-probe effect.
Deno.serve(createEdgeReceiver({env:Deno.env}));
