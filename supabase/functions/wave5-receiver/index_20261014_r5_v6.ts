import {createEdgeReceiver} from '../../../workers/wave5/edge_receiver_20261014_r5_v6.mjs';
import {withBoundedProviderDiagnostic} from '../../../workers/wave5/edge_route_20261014_r5_v6.mjs';
import {edgeConfiguration} from '../../../workers/wave5/edge_configuration.mjs';

// The unchanged handler authenticates before this single finite observation.
// Provider keys and URL values never reach the diagnostic sink.
Deno.serve(withBoundedProviderDiagnostic({
 handler:createEdgeReceiver({env:Deno.env}),env:Deno.env,
 configuredUrl:edgeConfiguration.url,worker:'receiver',
 observe:(classification:unknown)=>console.info(JSON.stringify(classification)),
}));
