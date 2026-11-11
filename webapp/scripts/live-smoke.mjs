import fs from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';
const root='/home/paulanthonyarriola/rescene-rhythm',base='https://rhythm.remineph.online';
const qa=JSON.parse(fs.readFileSync(root+'/backend/data/vps-deployment/qa-player.json','utf8'));
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
const context=await browser.newContext({viewport:{width:1600,height:960}});const page=await context.newPage();const errors=[];const checks={};
page.on('pageerror',e=>errors.push(e.message));
try{
 await page.goto(base);await page.locator('.lobby').waitFor();await page.screenshot({path:root+'/previews/webapp-live-lobby-desktop.png',fullPage:true});
 await page.getByRole('button',{name:'Enter your backstage'}).click();await page.getByLabel('Username',{exact:true}).fill(qa.username);await page.getByLabel('Password',{exact:true}).fill(qa.password);
 const resultPromise=page.waitForResponse(r=>r.url()===base+'/api/auth/login');await page.getByRole('dialog').getByRole('button',{name:'Sign in',exact:true}).click();const result=await resultPromise;assert.equal(result.status(),200);const data=await result.json();assert.ok(data.user);assert.equal('access_token' in data,false);assert.equal('refresh_token' in data,false);checks.tokens_private=true;
 await page.getByRole('dialog').waitFor({state:'hidden',timeout:60000});await page.getByText(qa.username,{exact:true}).waitFor();checks.login=true;
 const cookie=(await context.cookies()).find(c=>c.name==='__Host-rhythm');assert.ok(cookie?.httpOnly&&cookie?.secure&&cookie.sameSite==='Strict');assert.ok(cookie.expires>Date.now()/1000+29*86400);checks.cookie_30_days=true;
 await page.reload();await page.getByText(qa.username,{exact:true}).waitFor({timeout:60000});checks.persistent_login=true;
 for(const [label,heading] of [['Collection','Your collection.'],['Marketplace','Marketplace.'],['Rewards','A little more, every day.'],['Songs','The song library.'],['Rankings','In the spotlight.'],['Community','A little closer.']]){
  await page.locator('.sidebar nav').getByRole('button',{name:label,exact:true}).click();await page.getByRole('heading',{name:heading,exact:true}).waitFor();
  if(label==='Collection')await page.locator('.deck-grid').waitFor({timeout:60000});
  if(label==='Marketplace')await page.locator('.product').first().waitFor({timeout:60000});
  checks[label.toLowerCase()]=true;
  if(['Collection','Marketplace'].includes(label))await page.screenshot({path:root+'/previews/webapp-live-'+label.toLowerCase()+'-desktop.png',fullPage:true});
 }
 await page.locator('.player-button').click();await page.getByRole('heading',{name:'Player profile.'}).waitFor();await page.screenshot({path:root+'/previews/webapp-live-profile-desktop.png',fullPage:true});
 const statuses=await page.evaluate(async()=>{const out={};for(const endpoint of ['/session','/inventory','/shop/catalog','/account/security','/challenges']){const res=await fetch('/api'+endpoint);out[endpoint]=res.status;}const denied=await fetch('/api/runs',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});out['/runs']=denied.status;return out;});assert.ok(Object.entries(statuses).every(([p,status])=>status===(p==='/runs'?404:200)));checks.live_api=statuses;
 const initialMedia=await page.evaluate(async()=> (await (await fetch('/api/profile/media')).json()).media);
 if(!initialMedia.avatar){
  await page.getByLabel('Upload avatar',{exact:true}).setInputFiles(root+'/assets/art/cards/woni.jpg');await page.getByRole('status').filter({hasText:'Your photo is updated.'}).waitFor({timeout:60000});checks.avatar_upload=true;
  await page.getByRole('button',{name:'Remove avatar',exact:true}).click();await page.getByRole('button',{name:'Confirm removal'}).click();await page.getByRole('dialog').waitFor({state:'hidden',timeout:60000});checks.avatar_remove=true;
 }
 if(initialMedia.gallery.length===0){
  await page.getByLabel('Add gallery photo',{exact:true}).setInputFiles(root+'/assets/art/cards/minami.jpg');await page.locator('.gallery-photo').first().waitFor({timeout:60000});checks.gallery_upload=true;
  await page.locator('.gallery-photo').getByRole('button',{name:'Remove',exact:true}).click();await page.getByRole('button',{name:'Confirm removal'}).click();await page.getByRole('dialog').waitFor({state:'hidden',timeout:60000});checks.gallery_remove=true;
 }
 await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'Open navigation'}).click();await page.locator('.sidebar nav').getByRole('button',{name:'Lobby',exact:true}).click();await page.screenshot({path:root+'/previews/webapp-live-lobby-mobile.png',fullPage:true});checks.mobile_overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);assert.equal(checks.mobile_overflow,false);
 assert.equal(await page.locator('audio,video,canvas').count(),0);checks.no_playback=true;
 const download=await context.request.get(base+'/download',{maxRedirects:0});assert.equal(download.status(),302);assert.equal(download.headers().location,'https://api.remineph.online/download');checks.apk_redirect=true;
 const apk=await context.request.get('https://api.remineph.online/download',{headers:{Range:'bytes=0-1023'}});assert.equal(apk.status(),206);assert.equal((await apk.body()).length,1024);checks.apk_range=true;
 await page.locator('.player-button').click();await page.getByRole('button',{name:'Sign out',exact:true}).click();await page.getByRole('button',{name:'Enter your backstage'}).waitFor();assert.equal((await context.cookies()).some(c=>c.name==='__Host-rhythm'),false);checks.logout=true;
 assert.deepEqual(errors,[]);checks.browser_errors=errors;fs.writeFileSync(root+'/output/webapp-live-verification.json',JSON.stringify(checks,null,2));console.log(JSON.stringify(checks,null,2));
}finally{await context.close();await browser.close();}
