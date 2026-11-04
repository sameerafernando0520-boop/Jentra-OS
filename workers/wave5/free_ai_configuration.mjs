import {edgeConfiguration as bindings} from './edge_configuration.mjs';
import {cloudflareFreeModel} from './cloudflare_model_adapter.mjs';

// The owner's 2 November activation request selects Workers Free. Historical
// deployment entrypoints keep their original model configuration for readback.
export const freeAiConfiguration=Object.freeze({...bindings,model:Object.freeze({...bindings.model,
 provider:'cloudflare.workers-ai.free.v1',model:cloudflareFreeModel,freeOnly:true,paidFallback:false,bindProviderIdentity:true})});
