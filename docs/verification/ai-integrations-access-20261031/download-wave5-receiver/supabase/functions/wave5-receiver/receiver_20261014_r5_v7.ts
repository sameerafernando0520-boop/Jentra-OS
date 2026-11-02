import {createEdgeReceiver} from '../edge_receiver_20261014_r5_v7.mjs';
import {withBoundedProviderDiagnostic} from '../edge_route_20261014_r5_v6.mjs';
import {edgeConfiguration} from '../edge_configuration.mjs';

// Caller authentication stays in the reviewed handler. The V6 diagnostic
// still emits only its single finite configuration-shape observation.
Deno.serve(withBoundedProviderDiagnostic({
 handler:createEdgeReceiver({env:Deno.env}),env:Deno.env,
 configuredUrl:edgeConfiguration.url,worker:'receiver',
 observe:(classification:unknown)=>console.info(JSON.stringify(classification)),
}));
