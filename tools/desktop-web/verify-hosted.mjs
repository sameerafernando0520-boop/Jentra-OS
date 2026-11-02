import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {verifyRelease} from './prepare.mjs';

const [directory,address,label]=process.argv.slice(2);
if(!directory||!['preview','live'].includes(label))throw Error('Usage: node tools/desktop-web/verify-hosted.mjs <hosting-release-directory> <HTTPS-origin> preview|live');
const origin=new URL(address);
if(origin.protocol!=='https:'||origin.pathname!=='/'||origin.search||origin.hash||origin.port||origin.username||origin.password||!(origin.hostname==='jentra-os-desktop.web.app'||/^jentra-os-desktop--desktop-qa-[a-z0-9-]+\.web\.app$/.test(origin.hostname)))throw Error('Reviewed desktop Hosting origin required.');
const stage=await verifyRelease(directory);
const manifest=JSON.parse(await readFile(path.join(directory,'hosting-manifest.json'),'utf8'));
const attempt=Date.now();
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const checked=[];
const queue=[...manifest.files];
async function worker(){
 while(queue.length){
  const file=queue.shift();
  const response=await fetch(new URL(file.path,origin),{cache:'no-store',signal:AbortSignal.timeout(60000)});
  assert.equal(response.status,200,file.path);
  const bytes=Buffer.from(await response.arrayBuffer());
  assert.equal(bytes.length,file.bytes,file.path);
  assert.equal(hash(bytes),file.sha256,file.path);
  assert.match(response.headers.get('cache-control')??'',/no-store/);
  assert.equal(response.headers.get('x-content-type-options'),'nosniff');
  assert.equal(response.headers.get('x-frame-options'),'DENY');
  assert.ok(response.headers.get('content-security-policy')?.includes("script-src 'self' 'wasm-unsafe-eval'"));
  if(file.path.endsWith('.wasm'))assert.match(response.headers.get('content-type')??'',/^application\/wasm/);
  checked.push({path:file.path,status:200,sha256:hash(bytes),contentType:response.headers.get('content-type')});
 }
}
await Promise.all(Array.from({length:5},worker));
const missing=[];
for(const route of ['/assets/not-found.wasm','/canvaskit/not-found.wasm','/downloads/not-found.exe','/not-found-file.js','/.env.acceptance.json','/jentra-os-firebase-adminsdk-not-a-real-key.json']){
 const response=await fetch(new URL(route,origin),{signal:AbortSignal.timeout(30000)});
 assert.equal(response.status,404,route);missing.push({route,status:response.status});
}
const deep=await fetch(new URL('/login?redirect=%2Fdashboard',origin),{signal:AbortSignal.timeout(30000)});
assert.equal(deep.status,200);
assert.equal(hash(Buffer.from(await deep.arrayBuffer())),manifest.files.find(file=>file.path==='index.html').sha256);
const require=createRequire('C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:960},deviceScaleFactor:1});
const page=await context.newPage();
const errors=[],failures=[];
let blockedWrites=0;
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
page.on('requestfailed',request=>failures.push({path:new URL(request.url()).pathname,error:request.failure()?.errorText}));
await context.route('https://xpdoufauvrbdmxgngetv.supabase.co/**',route=>{
 if(!['GET','HEAD','OPTIONS'].includes(route.request().method())){blockedWrites++;return route.abort();}
 return route.continue();
});
try{
 await page.goto(origin.href,{waitUntil:'networkidle',timeout:90000});
 const semantics=page.locator('flt-semantics-placeholder');
 await semantics.waitFor({state:'attached',timeout:60000});
 await semantics.evaluate(element=>element.click());
 await page.getByRole('button',{name:'Sign in securely',exact:true}).waitFor({state:'visible',timeout:60000});
 await page.getByRole('button',{name:'Show password',exact:true}).click();
 await page.getByRole('button',{name:'Hide password',exact:true}).waitFor();
 await page.getByRole('button',{name:'Hide password',exact:true}).click();
 await page.screenshot({path:path.join(directory,`${label}-${attempt}-sign-in.png`),fullPage:true});
 await page.getByRole('button',{name:'Create an account',exact:true}).click();
 await page.getByText('Use at least 12 characters, including letters, numbers and symbols.',{exact:true}).waitFor();
 // Send real keyboard input after focus so Flutter's editing client, rather
 // than only its accessibility input element, receives and retains the text.
 for(const [name,value] of [['Work email','password-check@example.test'],['Password','Synthetic-no-number!'],['Confirm password','Synthetic-no-number!']]){
  const input=page.getByLabel(name,{exact:true});
  await input.click();
  // Let Flutter attach its editing client after pointer focus before typing.
  assert.equal(await input.evaluate(element=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(document.activeElement===element))))),true,`${name} must own keyboard focus`);
  await input.pressSequentially(value,{delay:15});
  assert.equal(await input.inputValue(),value,name);
 }
 await page.getByRole('button',{name:'Create account',exact:true}).click();
 // Flutter also announces validation through aria-live. Assert the rendered
 // field error rather than ambiguously selecting its screen-reader announcement.
 await page.locator('span').filter({hasText:/^Include letters, numbers and symbols\.$/}).waitFor();
 assert.equal(await page.locator('span').filter({hasText:/^Enter a valid email address\.$/}).count(),0,'The valid email must survive focus changes');
 assert.equal(await page.getByLabel('Work email',{exact:true}).inputValue(),'password-check@example.test');
 assert.equal(blockedWrites,0,'Invalid signup must never reach a backend write');
 await page.getByRole('button',{name:'Show confirmation password',exact:true}).click();
 await page.getByRole('button',{name:'Hide confirmation password',exact:true}).click();
 await page.setViewportSize({width:676,height:668});
 await page.getByRole('button',{name:'Show password',exact:true}).waitFor();
 await page.screenshot({path:path.join(directory,`${label}-${attempt}-signup-676.png`),fullPage:true});
 assert.deepEqual(errors,[],'Browser runtime/console errors');
 assert.deepEqual(failures,[],'Failed browser requests');
 const result={passed:true,origin:origin.origin,label,identity:manifest.identity,publicSha256:stage.publicSha256,verifiedPublicFiles:checked.length,files:checked.sort((a,b)=>a.path.localeCompare(b.path)),missing,spaDeepLink:true,signInVisible:true,passwordEyes:true,newAccountRule:'12 characters with letters, numbers and symbols',formEmailAccepted:true,passwordTypingVerified:true,invalidSignupBlockedBeforeNetwork:true,blockedWrites,consoleErrors:errors,failedRequests:failures,screenshots:[`${label}-${attempt}-sign-in.png`,`${label}-${attempt}-signup-676.png`],realLoginPerformed:false,backendChanged:false};
 const report=JSON.stringify(result,null,2)+'\n';
 const pointer=path.join(directory,`${label}-verification.json`);
 let previous;
 try{previous=await readFile(pointer);}catch(error){if(error.code!=='ENOENT')throw error;}
 if(previous)await writeFile(path.join(directory,`${label}-verification-previous-${attempt}.json`),previous,{flag:'wx'});
 await writeFile(path.join(directory,`${label}-verification-${attempt}.json`),report,{flag:'wx'});
 await writeFile(pointer,report);
 console.log(JSON.stringify({passed:true,origin:origin.origin,label,verifiedPublicFiles:checked.length,signInVisible:true,passwordEyes:true,invalidSignupBlockedBeforeNetwork:true,backendChanged:false}));
}catch(error){
 await page.screenshot({path:path.join(directory,`${label}-${attempt}-diagnostic.png`),fullPage:true}).catch(()=>{});
 console.error(JSON.stringify({errors,failures,blockedWrites,fields:await page.locator('input').evaluateAll(inputs=>inputs.map(input=>({label:input.getAttribute('aria-label'),type:input.type}))).catch(()=>[])}));
 throw error;
}finally{await context.close();await browser.close();}
