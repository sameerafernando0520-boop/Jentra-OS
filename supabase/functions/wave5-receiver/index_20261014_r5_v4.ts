import {createEdgeReceiver} from '../../../workers/wave5/edge_receiver_20261014_r5_v4.mjs';
import {withBoundedIngressDiagnostic} from '../../../workers/wave5/edge_route_20261014_r5_v4.mjs';
import {edgeConfiguration} from '../../../workers/wave5/edge_configuration.mjs';

// Exact-byte HMAC and live source/scope/subscription checks stay in the factory.
// Log at most one finite classification per isolate; no request values or keys.
Deno.serve(withBoundedIngressDiagnostic({
 handler:createEdgeReceiver({env:Deno.env}),endpointUrl:edgeConfiguration.receiverUrl.slice(0,-'/accept'.length),
 allowedRoutes:['/accept','/redirect','/timeout','/reject'],worker:'receiver',
 observe:(classification:unknown)=>console.info(JSON.stringify(classification)),
}));
