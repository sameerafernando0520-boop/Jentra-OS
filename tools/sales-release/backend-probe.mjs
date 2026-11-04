import { readFile, writeFile, mkdir } from 'node:fs/promises';
const config = JSON.parse(await readFile('build/sales-release/public-client.json','utf8'));
if(config.SUPABASE_URL !== 'https://xpdoufauvrbdmxgngetv.supabase.co') throw Error('PROJECT_MISMATCH');
const headers = {apikey:config.SUPABASE_PUBLISHABLE_KEY};
const result = {project:'xpdoufauvrbdmxgngetv',readOnly:true,at:new Date().toISOString(),checks:[]};
for(const [name,url,extra] of [
  ['public-auth-settings',`${config.SUPABASE_URL}/auth/v1/settings`,{}],
  ['anonymous-api-catalogue',`${config.SUPABASE_URL}/rest/v1/`,{Accept:'application/openapi+json'}],
]) {
  try {
    const response = await fetch(url,{headers:{...headers,...extra},signal:AbortSignal.timeout(20000)});
    const value = await response.json();
    if(name === 'public-auth-settings') {
      result.checks.push({name,status:response.status,emailEnabled:value.external?.email ?? null,signupDisabled:value.disable_signup ?? null});
    } else {
      const paths=Object.keys(value.paths||{});
      result.checks.push({name,status:response.status,pathCount:paths.length,fieldSalesPaths:paths.filter(p=>/field_sales/.test(p)),limit:'Only anonymous API exposure is observed. This does not certify authenticated portfolio APIs or legacy-path denial.'});
    }
  }catch(error) { result.checks.push({name,unavailable:true,error:error.name}); }
}
await mkdir('build/sales-release',{recursive:true});
await writeFile('build/sales-release/backend-readonly-20261030.json',JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
