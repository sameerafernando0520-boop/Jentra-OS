import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
const require=createRequire(import.meta.url);
const { chromium }=require('playwright');
const [baseUrl,output]=process.argv.slice(2);
await mkdir(output,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--disable-gpu','--disable-quic']});
const page=await browser.newPage({viewport:{width:1440,height:1000}});
const records=[];
const inspect=async label=>records.push({label,active:await page.evaluate(()=>({tag:document.activeElement?.tagName,html:document.activeElement?.outerHTML.slice(0,350)})),fields:await page.locator('input,textarea').evaluateAll(elements=>elements.map(e=>({tag:e.tagName,classes:e.className,role:e.getAttribute('role'),label:e.getAttribute('aria-label'),value:e.value,visible:e.getBoundingClientRect().width>0,focused:e===e.getRootNode().activeElement})))});
try {
  await page.goto(baseUrl,{waitUntil:'networkidle',timeout:90000});
  await page.getByText('Explore the preview',{exact:true}).click();
  await page.getByRole('button',{name:/^Catalogue(?:\s|$)/}).first().click();
  await page.getByRole('button',{name:'Start order with this product'}).first().click();
  await page.getByRole('button',{name:/^Customer(?:\s|$)/}).last().click();
  await page.getByRole('menuitem',{name:'Ceylon Home & Living',exact:true}).click();
  const quantity=page.getByRole('textbox',{name:'Quantity · piece'});
  await inspect('before focus');
  await quantity.click();
  await inspect('immediately after click');
  const editor=quantity;
  await editor.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await editor.focus();
  await inspect('native editor ready');
  await editor.press('ControlOrMeta+A');await editor.press('Backspace');
  await editor.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  if(await editor.inputValue()!=='')throw Error('Native editor did not clear');
  await editor.pressSequentially('1.125',{delay:50});
  await editor.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  if(await editor.inputValue()!=='1.125')throw Error('Native editor quantity differs');
  await inspect('after keyboard entry');
  await page.getByRole('button',{name:'Review order',exact:true}).click();
  await page.getByText(/Subtotal\s+LKR 1,406\.25/).waitFor();
  records.push({passed:true,subtotal:'1406.25'});
} catch(e) {records.push({passed:false,error:e.message});process.exitCode=1;}
finally {
  await page.screenshot({path:path.join(output,'page.png')});
  await writeFile(path.join(output,'page.aria.txt'),await page.locator('body').ariaSnapshot());
  await writeFile(path.join(output,'diagnostic.json'),JSON.stringify(records,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(records,null,2));await browser.close();
}
