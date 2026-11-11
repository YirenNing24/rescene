import fs from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';
const root='/home/paulanthonyarriola/rescene-rhythm',base='https://rhythm.remineph.online';
const qa=JSON.parse(fs.readFileSync(root+'/backend/data/vps-deployment/qa-player.json','utf8'));
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];
page.on('pageerror',e=>errors.push(e.message));
try {
 await page.goto(base);await page.locator('.lobby').waitFor();await page.getByRole('button',{name:'Enter your backstage'}).click();
 await page.getByLabel('Username',{exact:true}).fill(qa.username);await page.getByLabel('Password',{exact:true}).fill(qa.password);await page.getByRole('dialog').getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('dialog').waitFor({state:'hidden',timeout:60000});await page.locator('.sidebar nav').getByRole('button',{name:'Events',exact:true}).click();
 await page.getByRole('heading',{name:'Your PULSE missions'}).waitFor({timeout:60000});
 const data=await page.evaluate(async()=>{const r=await fetch('/api/events');return {status:r.status,data:await r.json()};});
 assert.equal(data.status,200);assert.equal(data.data.events[0].id,'pulse_first_scene_2026');assert.equal(data.data.events[0].status,'active');assert.equal(data.data.events[0].missions.length,7);
 await page.screenshot({path:root+'/previews/pulse-event-live-desktop.png',fullPage:true});
 await page.setViewportSize({width:390,height:844});await page.waitForTimeout(500);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.screenshot({path:root+'/previews/pulse-event-live-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);console.log('Live web event: active, seven missions, authenticated API, desktop and mobile verified.');
} finally {await browser.close();}
