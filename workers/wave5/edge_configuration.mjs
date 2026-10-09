// Public deployment bindings only. Installation, provisioning and deployment
// still require the separately hashed owner review.
export const edgeConfiguration=Object.freeze({
 projectId:'xpdoufauvrbdmxgngetv',url:'https://xpdoufauvrbdmxgngetv.supabase.co',
 runtimeId:'778237e3-3d4e-4871-8cc9-e08b07b989c7',
 workerUrl:'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime',
 receiverUrl:'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-receiver/accept',
 receiverSubscriptions:{accept:'58699e8a-28fd-4356-8cad-87ce46e17ddd',redirect:'2bdbd842-5b94-464b-85fc-22d722498831',
  timeout:'0961e194-dc0b-4632-8c2d-65686fc9f111',reject:'360e7a9d-08a5-4349-854f-c2343ce2ff5d'},
 maxDeliveryBatch:3,maxSubscriptionBatch:50,maxRequestBytes:65536,maxConcurrentRequests:8,
 model:{approved:true,revision:1,provider:'openai.responses.v1',model:'gpt-4.1-mini-2025-04-14',
  maximumCalls:4,maxTokensPerInvocation:'2000',inputMaxBytes:65536,outputMaxBytes:8192,
  store:false,background:false,tools:[],numericProjection:'pipeline.current_weighted.v1'},
});
