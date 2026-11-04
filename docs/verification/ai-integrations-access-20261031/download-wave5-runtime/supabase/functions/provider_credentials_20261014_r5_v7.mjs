// Privileged worker credentials only. Format validation never decodes a key
// or grants caller access. Only the existing server-supplied key is accepted.
export function serviceCredentialKind(value){
 if(typeof value!=='string'||value.length<32)return null;
 if(value.startsWith('sb_'))return /^sb_secret_[A-Za-z0-9_-]+$/.test(value)?'opaque_secret':null;
 if(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value))return 'legacy_jwt';
 return null;
}

// Opaque Supabase secret keys are API keys, not Bearer JWTs. Legacy service
// JWTs retain both headers. Never expose these headers in logs or responses.
export function serviceProviderHeaders(serviceKey){
 const kind=serviceCredentialKind(serviceKey);
 if(kind===null)throw Error('WORKER_CONFIGURATION_INVALID');
 return Object.freeze(kind==='legacy_jwt'
  ?{apikey:serviceKey,authorization:`Bearer ${serviceKey}`}
  :{apikey:serviceKey});
}
