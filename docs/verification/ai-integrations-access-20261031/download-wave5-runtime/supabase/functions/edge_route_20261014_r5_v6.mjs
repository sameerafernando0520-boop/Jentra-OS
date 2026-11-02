// The finite managed-hop observation binds the existing project hostname,
// default port and function namespace. Public endpoints remain HTTPS; the
// internal HTTP form is eligible only on this project's exact namespace.
const projectOrigin='https://xpdoufauvrbdmxgngetv.supabase.co';
const projectHttpOrigin='http://xpdoufauvrbdmxgngetv.supabase.co';
const platformOrigin='https://edge-runtime.supabase.com';
// Classification only: the HTTP platform hostname stays denied.
const platformHttpOrigin='http://edge-runtime.supabase.com';
const endpoints=Object.freeze({
 '/functions/v1/wave5-runtime':Object.freeze(['/schedule','/external/forecast','/model/suggestion']),
 '/functions/v1/wave5-receiver':Object.freeze(['/accept','/redirect','/timeout','/reject']),
});

function parseUrl(value){
 if(typeof value!=='string')return null;
 try{return new URL(value);}catch{return null;}
}
function exactHttpsUrl(value,url){
 // Require a canonical HTTPS URL without credentials or even empty query/hash
 // delimiters. No forwarded headers or other request fields are consulted.
 return url!==null&&url.protocol==='https:'&&value===url.href
  &&url.href===url.origin+url.pathname&&!url.username&&!url.password;
}
function exactRequestUrl(value,url){
 return url!==null&&(url.protocol==='https:'||url.origin===projectHttpOrigin)
  &&value===url.href&&url.href===url.origin+url.pathname&&!url.username&&!url.password;
}
function configuredEndpoint(endpointUrl){
 const base=parseUrl(endpointUrl);
 if(!exactHttpsUrl(endpointUrl,base)||base.origin!==projectOrigin)return null;
 const routes=endpoints[base.pathname];
 if(!routes)return null;
 return {base,namespace:base.pathname.slice('/functions/v1'.length),routes};
}

export function edgeRoute(requestUrl,endpointUrl,allowedRoutes){
 const url=parseUrl(requestUrl),endpoint=configuredEndpoint(endpointUrl);
 if(!endpoint||!Array.isArray(allowedRoutes)||!exactRequestUrl(requestUrl,url))return null;
 const prefixes=url.origin===projectOrigin?[endpoint.base.pathname,endpoint.namespace]
  :url.origin===projectHttpOrigin?[endpoint.namespace]
  :url.origin===platformOrigin?[endpoint.namespace]:[];
 for(const prefix of prefixes){
  if(!url.pathname.startsWith(prefix+'/'))continue;
  const route=url.pathname.slice(prefix.length);
  if(endpoint.routes.includes(route)&&allowedRoutes.includes(route))return route;
 }
 return null;
}

// A finite classification, never the URL, host, headers, body or method. This
// reports the actual handler input only after a separately approved deployment.
export function classifyEdgeIngress(requestUrl,endpointUrl,allowedRoutes){
 const url=parseUrl(requestUrl),endpoint=configuredEndpoint(endpointUrl);
 const originClass=!url?'invalid':url.origin===projectOrigin?'public_project'
  :url.origin===projectHttpOrigin?'public_project_http'
  :url.origin===platformOrigin?'platform_runtime':url.origin===platformHttpOrigin?'platform_runtime_http':'other';
 const pathClass=!url||!endpoint?'invalid'
  :url.pathname.startsWith(endpoint.base.pathname+'/')?'public_function'
  :url.pathname.startsWith(endpoint.namespace+'/')?'function_namespace':'other';
 const authority=typeof requestUrl==='string'?/^https?:\/\/([^/?#]*)/i.exec(requestUrl)?.[1]:undefined;
 return Object.freeze({
  originClass,pathClass,
  hostnameClass:!url?'invalid':url.hostname==='edge-runtime.supabase.com'?'platform_host'
   :url.hostname==='xpdoufauvrbdmxgngetv.supabase.co'?'project_host':'other',
  portClass:!url?'invalid':url.port===''?'default':'other',
  https:url?.protocol==='https:',
  query:typeof requestUrl==='string'&&requestUrl.includes('?'),
  hash:typeof requestUrl==='string'&&requestUrl.includes('#'),
  userinfo:!!(url?.username||url?.password||authority?.includes('@')),
  routeRecognized:edgeRoute(requestUrl,endpointUrl,allowedRoutes)!==null,
 });
}

// One observation per factory instance/isolate, including concurrent requests.
// A diagnostic sink failure never changes the unchanged authenticated handler.
export function withBoundedIngressDiagnostic({handler,endpointUrl,allowedRoutes,worker,observe}){
 if(typeof handler!=='function'||typeof observe!=='function'||!configuredEndpoint(endpointUrl)
  ||!Array.isArray(allowedRoutes)||!['runtime','receiver'].includes(worker))throw Error('INGRESS_CONFIGURATION_INVALID');
 let remaining=1;
 return req=>{
  if(remaining>0){
   remaining--;
   try{observe(Object.freeze({kind:'wave5_ingress_v5',worker,...classifyEdgeIngress(req.url,endpointUrl,allowedRoutes)}));}catch{}
  }
  return handler(req);
 };
}

// Provider configuration classification only. No key/URL is parsed or emitted.
// Module scope bounds every entrypoint in this isolate to one attempted sample.
let providerDiagnosticRemaining=1;
const providerUrlClasses=Object.freeze(['exact_configured_https','exact_configured_https_with_slash','exact_project_http','missing','other']);
const serviceRoleShapes=Object.freeze(['legacy_jwt','opaque_secret_style','missing','other']);
function providerEnvValue(env,name){return typeof env.get==='function'?env.get(name):env[name];}
export function classifyProviderEnvironment(env,configuredUrl){
 if(configuredUrl!==projectOrigin)throw Error('PROVIDER_DIAGNOSTIC_CONFIGURATION_INVALID');
 const url=providerEnvValue(env,'SUPABASE_URL'),serviceRole=providerEnvValue(env,'SUPABASE_SERVICE_ROLE_KEY');
 const dictionary=providerEnvValue(env,'SUPABASE_SECRET_KEYS');
 const supabaseUrlClass=url===configuredUrl?'exact_configured_https'
  :url===configuredUrl+'/'?'exact_configured_https_with_slash'
  :url===projectHttpOrigin?'exact_project_http'
  :url===undefined||url===null||url===''?'missing':'other';
 const serviceRoleShape=typeof serviceRole==='string'&&/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(serviceRole)?'legacy_jwt'
  :typeof serviceRole==='string'&&/^sb_secret_[A-Za-z0-9_-]+$/.test(serviceRole)?'opaque_secret_style'
  :serviceRole===undefined||serviceRole===null||serviceRole===''?'missing':'other';
 if(!providerUrlClasses.includes(supabaseUrlClass)||!serviceRoleShapes.includes(serviceRoleShape))throw Error('PROVIDER_DIAGNOSTIC_CLASS_INVALID');
 return Object.freeze({supabaseUrlClass,serviceRoleShape,secretKeysDictionaryPresent:typeof dictionary==='string'&&dictionary.length>0});
}

// The original handler runs first. Diagnostic reads/throws/rejected sinks do
// not replace, await or change its response or error. No request field is read.
export function withBoundedProviderDiagnostic({handler,env,configuredUrl,worker,observe}){
 if(typeof handler!=='function'||typeof observe!=='function'||configuredUrl!==projectOrigin
  ||!['runtime','receiver'].includes(worker))throw Error('PROVIDER_DIAGNOSTIC_CONFIGURATION_INVALID');
 return req=>{
  const sample=providerDiagnosticRemaining>0;
  if(sample)providerDiagnosticRemaining--;
  const diagnose=()=>{
   if(!sample)return;
   try{
    const descriptor=Object.freeze({kind:'wave5_provider_v6',worker,...classifyProviderEnvironment(env,configuredUrl)});
    const pending=observe(descriptor);
    if(pending&&typeof pending.catch==='function')pending.catch(()=>{});
   }catch{}
  };
  try{
   const output=handler(req);
   if(output&&typeof output.then==='function')return output.then(response=>{diagnose();return response;},error=>{diagnose();throw error;});
   diagnose();return output;
  }catch(error){diagnose();throw error;}
 };
}
