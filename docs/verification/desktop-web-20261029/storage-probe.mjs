import {createRequire} from 'node:module';
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire('C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/package.json');
const {chromium}=require('playwright');
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const context=await browser.newContext();
const page=await context.newPage();
const errors=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
try{
 await page.goto('http://127.0.0.1:51431/',{waitUntil:'domcontentloaded',timeout:30000});
 await page.waitForFunction(()=>typeof window.jentraStorageProbeResult==='string',{},{timeout:120000});
 const result=JSON.parse(await page.evaluate(()=>window.jentraStorageProbeResult));
 const files=['packages/jentra_platform/test/support/browser_storage_scenarios.dart','docs/verification/desktop-web-20261029/browser_storage_probe.dart'];
 result.sources=await Promise.all(files.map(async file=>({path:file,sha256:createHash('sha256').update(await readFile(file)).digest('hex')})));
 result.compiler='Flutter 3.47.5 release JavaScript, locally bundled renderer';
 result.unitHarness='SDK browser harness blocked by Windows CanvasKit URL routing; these same four scenarios ran through the compiled probe';
 result.consoleErrors=errors;
 console.log(JSON.stringify(result));
 await writeFile(path.resolve('docs/verification/desktop-web-20261029/browser-storage-probe.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
 assert.equal(result.passed,true,'All durable browser storage scenarios');
 assert.equal(result.scenarios.length,4);
 assert.deepEqual(errors,[],'Browser runtime/console errors');
}catch(error){
 console.error(JSON.stringify({errors,progress:await page.evaluate(()=>window.jentraStorageProbeProgress??'entrypoint not reached').catch(()=>null),body:await page.locator('body').innerText().catch(()=>null)}));
 throw error;
}finally{await context.close();await browser.close();}
