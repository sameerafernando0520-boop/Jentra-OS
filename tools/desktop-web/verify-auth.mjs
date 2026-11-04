// Controlled SDK/browser acceptance only. Every Supabase HTTP/WebSocket request
// is intercepted locally: no account, email or company record is created.
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const [address,directory,label]=process.argv.slice(2);
if(!['local','preview','live'].includes(label))throw Error('Explicit verification label required.');
const origin=new URL(address);
if(!(origin.protocol==='https:'&&(origin.hostname==='jentra-os-desktop.web.app'||/^jentra-os-desktop--desktop-qa-[a-z0-9-]+\.web\.app$/.test(origin.hostname))||origin.origin==='http://127.0.0.1:51434'))throw Error('Owned app origin required.');
const output=path.resolve(directory);await mkdir(output,{recursive:true});
const require=createRequire('C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const actor='10000000-0000-0000-0000-000000000021';
const email='auth-probe@example.test',password='Synthetic-password-7!';
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const contexts=[];const outcomes=[];
function user(){return{id:actor,aud:'authenticated',role:'authenticated',email,created_at:'2026-10-29T00:00:00Z',app_metadata:{},user_metadata:{},identities:[]};}
function session(){
 const exp=Math.floor(Date.now()/1000)+3600;
 const jwt=[Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),Buffer.from(JSON.stringify({sub:actor,aud:'authenticated',role:'authenticated',aal:'aal1',exp})).toString('base64url'),'synthetic-signature'].join('.');
 return{access_token:jwt,refresh_token:'synthetic-refresh',expires_in:3600,expires_at:exp,token_type:'bearer',user:{...user(),email_confirmed_at:'2026-10-29T00:00:00Z'}};
}
async function fresh(){
 const context=await browser.newContext({viewport:{width:1280,height:960}});contexts.push(context);
 const events=[],errors=[];let challenge;
 await context.routeWebSocket(/^wss:\/\/xpdoufauvrbdmxgngetv\.supabase\.co\//,socket=>socket.close({code:1000,reason:'Controlled local test'}));
 await context.route('https://xpdoufauvrbdmxgngetv.supabase.co/**',async route=>{
  const request=route.request(),url=new URL(request.url());
  const headers={'content-type':'application/json','x-supabase-api-version':'2024-01-01','access-control-allow-origin':origin.origin,'access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,OPTIONS'};
  if(request.method()==='OPTIONS')return route.fulfill({status:204,headers,body:''});
  const body=request.postData()?JSON.parse(request.postData()):{};
  let response=[];
  if(url.pathname==='/auth/v1/signup'||url.pathname==='/auth/v1/resend'){
   assert.equal(body.email,email);
   assert.equal(url.searchParams.get('redirect_to'),origin.origin+'/');
   if(body.code_challenge)challenge=body.code_challenge;
   events.push({kind:url.pathname.endsWith('/signup')?'signup':'resend',redirectCorrect:true,pkce:!!body.code_challenge});
   response=url.pathname.endsWith('/signup')?user():{};
  }else if(url.pathname==='/auth/v1/token'){
   const grant=url.searchParams.get('grant_type');
   assert.ok(['pkce','password'].includes(grant));
   if(grant==='pkce'){
    assert.equal(body.auth_code,'synthetic-confirmation-code');
    assert.ok(body.code_verifier?.length>=43);
    assert.equal(createHash('sha256').update(body.code_verifier).digest('base64url'),challenge);
   }else{assert.equal(body.email,email);assert.equal(body.password,password);}
   events.push({kind:grant,verifierMatched:grant==='pkce'});response=session();
  }else if(url.pathname==='/auth/v1/user')response=user();
  else if(url.pathname==='/auth/v1/settings')response={external:{email:true,google:false}};
  else if(!url.pathname.startsWith('/rest/v1/'))throw Error('Unexpected controlled Auth endpoint.');
  return route.fulfill({status:200,headers,body:JSON.stringify(response)});
 });
 const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
 return{context,page,events,errors};
}
async function accessible(page){
 const placeholder=page.locator('flt-semantics-placeholder');
 await placeholder.waitFor({state:'attached',timeout:60000});await placeholder.evaluate(element=>element.click());
}
async function type(page,name,value){
 const input=page.getByLabel(name,{exact:true});await input.click();
 // Flutter attaches its editing client on a frame after pointer focus. Wait
 // for that handoff, then require actual keyboard text to survive unchanged.
 assert.equal(await input.evaluate(element=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(document.activeElement===element))))),true,`${name} must own keyboard focus`);
 await input.pressSequentially(value,{delay:15});assert.equal(await input.inputValue(),value);
}
async function storedActor(page){return page.evaluate(id=>Object.values(localStorage).some(value=>value.includes(id)),actor);}
try{
 const signup=await fresh();await signup.page.goto(origin.href,{waitUntil:'networkidle',timeout:90000});await accessible(signup.page);
 await signup.page.getByRole('button',{name:'Create an account',exact:true}).click();
 await type(signup.page,'Work email',email);await type(signup.page,'Password',password);await type(signup.page,'Confirm password',password);
 await signup.page.getByRole('button',{name:'Create account',exact:true}).click();
 await signup.page.getByText('Confirm your email',{exact:true}).waitFor();
 assert.equal(signup.events.filter(event=>event.kind==='signup').length,1);assert.equal(signup.events[0].pkce,true);
 await signup.page.goto(origin.href,{waitUntil:'networkidle'});await accessible(signup.page);
 await signup.page.getByRole('button',{name:'Need to confirm your email?',exact:true}).click();
 await type(signup.page,'Work email',email);
 await signup.page.getByRole('button',{name:'Resend confirmation email',exact:true}).click();
 await signup.page.getByText('Wait a minute before requesting another email.',{exact:true}).waitFor();
 assert.equal(signup.events.filter(event=>event.kind==='resend').length,1);
 await signup.page.goto(origin.origin+'/?code=synthetic-confirmation-code',{waitUntil:'networkidle',timeout:90000});
 await signup.page.waitForFunction(id=>Object.values(localStorage).some(value=>value.includes(id)),actor,{timeout:30000});
 assert.equal(signup.events.filter(event=>event.kind==='pkce').length,1);assert.equal(await storedActor(signup.page),true);
 assert.equal(new URL(signup.page.url()).searchParams.has('code'),false);assert.ok(!signup.page.url().includes('synthetic-confirmation-code'));
 await signup.page.goto(origin.origin+'/?code=must-not-replace-account',{waitUntil:'networkidle'});
 assert.equal(signup.events.filter(event=>event.kind==='pkce').length,1);assert.equal(await storedActor(signup.page),true);
 assert.deepEqual(signup.errors,[]);
 outcomes.push({scenario:'signup-resend-PKCE-and-session-preservation',passed:true,events:signup.events});

 const signin=await fresh();await signin.page.goto(origin.href,{waitUntil:'networkidle'});await accessible(signin.page);
 await type(signin.page,'Work email',email);await type(signin.page,'Password',password);
 await signin.page.getByRole('button',{name:'Sign in securely',exact:true}).click();
 await signin.page.waitForFunction(id=>Object.values(localStorage).some(value=>value.includes(id)),actor,{timeout:30000});
 assert.equal(signin.events.filter(event=>event.kind==='password').length,1);assert.deepEqual(signin.errors,[]);
 outcomes.push({scenario:'password-sign-in',passed:true});

 for(const [suffix,message] of [
  ['?error=access_denied&error_code=otp_expired&error_description=SYNTHETIC_PRIVATE','This confirmation link has expired or has already been used. Try signing in, or request a fresh email.'],
  ['#access_token=SYNTHETIC_PRIVATE&refresh_token=SYNTHETIC_PRIVATE','Copy the original confirmation link from your email. The localhost address from the browser cannot be used here.'],
 ]){
  const failure=await fresh();await failure.page.goto(origin.origin+'/'+suffix,{waitUntil:'networkidle'});await accessible(failure.page);
  // Assert the rendered error, separately from Flutter's aria-live copy.
  await failure.page.locator('span').filter({hasText:message}).waitFor();
  assert.ok(!failure.page.url().includes('SYNTHETIC_PRIVATE'));
  assert.equal(await failure.page.evaluate(()=>Object.values(localStorage).some(value=>value.includes('SYNTHETIC_PRIVATE'))),false);
  assert.equal(await storedActor(failure.page),false);assert.deepEqual(failure.events,[]);assert.deepEqual(failure.errors,[]);
  outcomes.push({scenario:suffix.startsWith('?')?'expired-callback-cleanup':'implicit-token-rejected',passed:true});
 }
 const report={passed:true,origin:origin.origin,label,scenarios:outcomes,transport:'Supabase fully mocked; WebSocket connections blocked',realEmailSent:false,realAccountCreated:false,backendChanged:false};
 await writeFile(path.join(output,`${label}-auth-verification.json`),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify(report));
}catch(error){
 for(let index=0;index<contexts.length;index++)for(const page of contexts[index].pages())await page.screenshot({path:path.join(output,`${label}-auth-diagnostic-${index}-${Date.now()}.png`),fullPage:true}).catch(()=>{});
 throw error;
}finally{for(const context of contexts)await context.close();await browser.close();}
