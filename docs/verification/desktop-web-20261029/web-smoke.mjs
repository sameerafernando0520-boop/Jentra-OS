import {createRequire} from 'node:module';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import path from 'node:path';
const require=createRequire('C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const origin='http://127.0.0.1:51430';
const output=path.resolve('docs/verification/desktop-web-20261029');
const checks=[];
for(const [route,type] of [
 ['/', 'text/html'],['/main.dart.js','text/javascript'],
 ['/assets/packages/jentra_platform/assets/web/sqlite3.wasm','application/wasm'],
 ['/assets/packages/jentra_platform/assets/web/drift_worker.js','text/javascript'],
 ['/canvaskit/chromium/canvaskit.wasm','application/wasm'],
]){
 const response=await fetch(origin+route);
 assert.equal(response.status,200,route);
 assert.ok(response.headers.get('content-type').startsWith(type),route);
 assert.equal(response.headers.get('cache-control'),'no-store');
 assert.equal(response.headers.get('x-content-type-options'),'nosniff');
 checks.push({route,status:response.status,type:response.headers.get('content-type')});
 await response.arrayBuffer();
}
const denied=await fetch(origin+'/.env.acceptance.json');
assert.equal(denied.status,404);
checks.push({secretFileUnavailable:true,status:denied.status});
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:960},deviceScaleFactor:1});
const page=await context.newPage();
const errors=[];const failedRequests=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
page.on('requestfailed',request=>failedRequests.push({url:new URL(request.url()).origin+new URL(request.url()).pathname,error:request.failure()?.errorText}));
try{
 await page.goto(origin,{waitUntil:'networkidle',timeout:120000});
 const semantics=page.locator('flt-semantics-placeholder');
 await semantics.waitFor({state:'attached',timeout:60000});
 await semantics.evaluate(element=>element.click());
 await page.getByRole('button',{name:'Sign in securely',exact:true}).waitFor({state:'visible',timeout:60000});
 assert.equal(await page.getByRole('textbox').count()>=1,true);
 assert.equal(await page.evaluate(()=>isSecureContext),true);
 const text=await page.locator('body').innerText();
 assert.match(text,/Welcome back/);
 await page.screenshot({path:path.join(output,'web-sign-in-1440.png'),fullPage:true});
 assert.deepEqual(errors,[],'Browser console/runtime errors');
 assert.deepEqual(failedRequests,[],'Failed browser requests');
 const result={passed:true,checks,signInVisible:true,secureContext:true,consoleErrors:errors,failedRequests,realLoginPerformed:false,backendMutations:false,hosted:false};
 await writeFile(path.join(output,'web-smoke.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify(result));
}catch(error){
 await page.screenshot({path:path.join(output,'web-smoke-diagnostic.png'),fullPage:true});
 console.error(JSON.stringify({errors,failedRequests,body:(await page.locator('body').innerText()).slice(0,2000)}));
 throw error;
}finally{await context.close();await browser.close();}
