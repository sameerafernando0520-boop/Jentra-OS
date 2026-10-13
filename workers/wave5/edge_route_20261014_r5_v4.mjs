// Source-only candidate. A managed handler's actual Request URL is not yet
// observed. Only this reviewed project and the exact Supabase runtime origin
// are eligible; the internal form requires the fixed function-name namespace.
const projectOrigin='https://xpdoufauvrbdmxgngetv.supabase.co';
const platformOrigin='https://edge-runtime.supabase.com';
// Classification only: the route allowlist stays HTTPS-only in this revision.
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
function configuredEndpoint(endpointUrl){
 const base=parseUrl(endpointUrl);
 if(!exactHttpsUrl(endpointUrl,base)||base.origin!==projectOrigin)return null;
 const routes=endpoints[base.pathname];
 if(!routes)return null;
 return {base,namespace:base.pathname.slice('/functions/v1'.length),routes};
}

export function edgeRoute(requestUrl,endpointUrl,allowedRoutes){
 const url=parseUrl(requestUrl),endpoint=configuredEndpoint(endpointUrl);
 if(!endpoint||!Array.isArray(allowedRoutes)||!exactHttpsUrl(requestUrl,url))return null;
 const prefixes=url.origin===projectOrigin?[endpoint.base.pathname,endpoint.namespace]
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
   try{observe(Object.freeze({kind:'wave5_ingress_v4',worker,...classifyEdgeIngress(req.url,endpointUrl,allowedRoutes)}));}catch{}
  }
  return handler(req);
 };
}
