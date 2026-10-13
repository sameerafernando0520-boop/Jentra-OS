// Supabase's published routing contract prefixes in-function paths with the
// function name. Accept that namespace and the public URL namespace exactly.
// Both forms retain the configured HTTPS origin and all downstream auth checks.
export function edgeRoute(requestUrl,endpointUrl,allowedRoutes){
 let url,base;try{url=new URL(requestUrl);base=new URL(endpointUrl);}catch{return null;}
 if(base.protocol!=='https:'||url.origin!==base.origin||url.username||url.password||url.search||url.hash)return null;
 if(!base.pathname.startsWith('/functions/v1/'))return null;
 const platformBase=base.pathname.slice('/functions/v1'.length);
 for(const prefix of [base.pathname,platformBase]){
  if(!url.pathname.startsWith(prefix+'/'))continue;
  const route=url.pathname.slice(prefix.length);
  if(allowedRoutes.includes(route))return route;
 }
 return null;
}
