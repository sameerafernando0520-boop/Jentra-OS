import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const baseUrl = process.argv[2] || 'http://127.0.0.1:8396';
const out = path.resolve(process.argv[3] || 'output/playwright/jentra-sales-local');
await mkdir(out, {recursive: true});
const launchArgs=['--disable-gpu',...(process.argv[4]==='tcp'?['--disable-quic']:[])];
const browser = await chromium.launch({channel:'chrome', headless:true, args:launchArgs});
const results = [];
try {
  for (const [name, width, height] of [['desktop',1440,1000],['tablet',1024,900],['phone',390,844]]) {
    const context = await browser.newContext({viewport:{width,height}, deviceScaleFactor:1, reducedMotion:'reduce'});
    const page = await context.newPage();
    const navigate = label => page.getByRole('button',{name:new RegExp(`^${label}(?:\\s|$)`)})
      .or(page.getByRole('tab',{name:new RegExp(`^${label}(?:\\s|$)`)})).first().click();
    const settleInput=field=>field.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    const replaceText=async(label,value)=>{
      const field=page.getByRole('textbox',{name:label});
      // Flutter initializes its semantic input value after focus. DOM fill alone
      // does not update the text controller; use the active keyboard editor.
      await field.click();await settleInput(field);await field.focus();
      await field.press('ControlOrMeta+A');await field.press('Backspace');
      await settleInput(field);assert.equal(await field.inputValue(),'');
      if(value)await field.pressSequentially(value,{delay:50});
      await settleInput(field);assert.equal(await field.inputValue(),value);
    };
    const errors = [], backend = [], failed = [], navigationAborts=[];
    const inFlight=new Set(),intentionalNavigation=new Map();
    page.on('request',r=>inFlight.add(r));
    page.on('requestfinished',r=>inFlight.delete(r));
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error') errors.push(m.text());});
    page.on('requestfailed',r=>{
      inFlight.delete(r);
      const record={url:r.url(),error:r.failure()?.errorText};
      if(record.error==='net::ERR_ABORTED'&&intentionalNavigation.has(r))navigationAborts.push({...record,reason:intentionalNavigation.get(r)});
      else failed.push(record);
    });
    await page.route('https://xpdoufauvrbdmxgngetv.supabase.co/**', async route=>{
      backend.push({method:route.request().method(),path:new URL(route.request().url()).pathname});
      await route.abort();
    });
    try {
      await page.goto(baseUrl,{waitUntil:'domcontentloaded',timeout:120000});
      await page.getByText('Explore the preview',{exact:true}).waitFor({timeout:90000});
      await page.screenshot({path:path.join(out,`${name}-login.png`)});
      await page.getByText('Explore the preview',{exact:true}).click();
      await page.getByText('A good day to connect.',{exact:true}).waitFor({timeout:30000});
      assert.equal(await page.getByText('Saved drafts could not be opened.',{exact:false}).count(),0);
      await page.screenshot({path:path.join(out,`${name}-today.png`)});
      console.log(`${name}: compiled login and Today rendered`);
      await writeFile(path.join(out,`${name}-today.aria.txt`),await page.locator('body').ariaSnapshot());
      await navigate('Customers');
      await page.getByText('Your customers',{exact:true}).waitFor();
      await replaceText('Search customers','Metro Essentials');
      await page.getByRole('button',{name:/Metro Essentials/}).first().waitFor();
      assert.equal(await page.getByRole('button',{name:/^CH Ceylon Home & Living/}).count(),0);
      await page.screenshot({path:path.join(out,`${name}-customers.png`)});
      await replaceText('Search customers','');
      await navigate('Orders');
      await page.getByText('Orders, without loose ends.',{exact:true}).waitFor();
      await page.getByRole('checkbox',{name:'Company review',exact:true}).click();
      await page.getByRole('button',{name:/Lanka Retail Collective/}).first().waitFor();
      await page.screenshot({path:path.join(out,`${name}-orders.png`)});
      console.log(`${name}: customer search and order filters passed`);
      if(name === 'desktop') {
        await navigate('Catalogue');
        await page.getByText('A catalogue worth knowing.',{exact:true}).waitFor();
        await page.screenshot({path:path.join(out,`${name}-catalogue.png`)});
        await page.getByRole('button',{name:'Start order with this product'}).first().click();
        await writeFile(path.join(out,'order-editor.aria.txt'),await page.locator('body').ariaSnapshot());
        await page.getByRole('button',{name:/^Customer(?:\s|$)/}).last().click();
        await page.getByRole('menuitem',{name:'Ceylon Home & Living',exact:true}).click();
        await replaceText('Quantity · piece','1.125');
        await page.getByRole('button',{name:'Review order',exact:true}).click();
        await page.getByText(/Subtotal\s+LKR 1,406\.25/).waitFor();
        await page.getByText(/Not saved yet.*24 hours/).waitFor();
        await page.screenshot({path:path.join(out,'desktop-order-review.png')});
        await page.getByRole('button',{name:'Save local draft',exact:true}).click();
        await page.getByText(/Preview draft saved on this device. No order was submitted./).first().waitFor();
        for(const request of inFlight)intentionalNavigation.set(request,'explicit reload');
        await page.reload({waitUntil:'domcontentloaded'});
        await page.getByText('Explore the preview',{exact:true}).waitFor({timeout:90000});
        await page.getByText('Explore the preview',{exact:true}).click();
        await navigate('Orders');
        await page.getByRole('checkbox',{name:'Local draft',exact:true}).click();
        await page.getByRole('button',{name:/Ceylon Home & Living.*LKR 1,406\.25/}).waitFor();
        await page.screenshot({path:path.join(out,'desktop-restored-draft.png')});
        await page.getByRole('button',{name:/Ceylon Home & Living.*LKR 1,406\.25/}).click();
        await page.getByRole('button',{name:'Continue editing',exact:true}).click();
        await replaceText('Quantity · piece','2.125');
        await page.getByRole('button',{name:'Close order editor',exact:true}).click();
        await page.getByText('Discard unsaved changes?',{exact:true}).waitFor();
        await page.getByRole('button',{name:'Keep editing',exact:true}).click();
        await page.getByRole('textbox',{name:'Quantity · piece'}).waitFor();
        await page.getByRole('button',{name:'Close order editor',exact:true}).click();
        await page.getByRole('button',{name:'Discard changes',exact:true}).click();
        await page.getByRole('button',{name:/Ceylon Home & Living.*LKR 1,406\.25/}).waitFor();
        await page.getByRole('button',{name:'Switch to dark theme'}).click();
        await page.screenshot({path:path.join(out,'desktop-dark.png')});
      }
      assert.deepEqual(errors,[]); assert.deepEqual(backend,[]); assert.deepEqual(failed,[]);
      results.push({name,width,height,passed:true,errors,backendRequests:backend,failedRequests:failed,navigationAborts});
      console.log(`${name}: passed with no runtime errors or backend requests`);
    } catch(error) {
      await page.screenshot({path:path.join(out,`${name}-failure.png`)}).catch(()=>{});
      await writeFile(path.join(out,`${name}-failure.aria.txt`),await page.locator('body').ariaSnapshot().catch(()=>''));
      results.push({name,width,height,passed:false,error:error.message,errors,backendRequests:backend,failedRequests:failed,navigationAborts});
      console.log(`${name}: failed: ${error.message}`);
    } finally {
      for(const request of inFlight)intentionalNavigation.set(request,'test context close');
      await context.close();
    }
  }
} finally {
  await browser.close();
  await writeFile(path.join(out,'browser-verification.json'),JSON.stringify({baseUrl,launchArgs,results},null,2)+'\n');
}
console.log(JSON.stringify({baseUrl,passed:results.filter(r=>r.passed).length,total:results.length,output:out}));
if(results.some(r=>!r.passed)) process.exitCode=1;
