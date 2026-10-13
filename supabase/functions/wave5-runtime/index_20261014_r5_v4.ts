import {createEdgeRuntime} from '../../../workers/wave5/edge_runtime_20261014_r5_v4.mjs';
import {withBoundedIngressDiagnostic} from '../../../workers/wave5/edge_route_20261014_r5_v4.mjs';
import {edgeConfiguration} from '../../../workers/wave5/edge_configuration.mjs';

// Custom schedule/external/caller authentication stays in the reviewed factory.
// Log at most one finite classification per isolate; no request values or keys.
Deno.serve(withBoundedIngressDiagnostic({
 handler:createEdgeRuntime({env:Deno.env}),endpointUrl:edgeConfiguration.workerUrl,
 allowedRoutes:['/schedule','/external/forecast','/model/suggestion'],worker:'runtime',
 observe:(classification:unknown)=>console.info(JSON.stringify(classification)),
}));
