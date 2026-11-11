import fs from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '@playwright/test';
const root='/home/paulanthonyarriola/rescene-rhythm',base='https://rhythm.remineph.online';
const qa=JSON.parse(fs.readFileSync(root+'/backend/data/vps-deployment/qa-player.json','utf8'));
const browser=await chromium.launch({channel:'chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
try{
 await page.goto(base);await page.locator('.lobby').waitFor();await page.getByRole('button',{name:'Enter your backstage'}).click();await page.getByLabel('Username',{exact:true}).fill(qa.username);await page.getByLabel('Password',{exact:true}).fill(qa.password);await page.getByRole('dialog').getByRole('button',{name:'Sign in',exact:true}).click();await page.getByRole('dialog').waitFor({state:'hidden',timeout:60000});
 await page.locator('.sidebar nav').getByRole('button',{name:'Songs',exact:true}).click();await page.locator('.song-mastery summary').waitFor({timeout:60000});await page.locator('.song-mastery summary').click();await page.getByText('Opening note',{exact:true}).waitFor();await page.screenshot({path:root+'/previews/song-mastery-live-web.png',fullPage:true});
 await page.locator('.sidebar nav').getByRole('button',{name:'Duet',exact:true}).click();await page.getByRole('heading',{name:'Your weekly duet.'}).waitFor();
 const values=await page.evaluate(async()=>{const result={};for(const path of ['/mastery/38c9a4926480','/coop','/events']){const response=await fetch('/api'+path);result[path]={status:response.status,data:await response.json()};}return result;});
 assert.equal(values['/mastery/38c9a4926480'].status,200);assert.equal(values['/mastery/38c9a4926480'].data.mastery.milestones.length,6);assert.equal(values['/coop'].status,200);assert.equal(values['/events'].status,200);assert.ok(values['/events'].data.events.some(e=>e.id.startsWith('weekly_')));
 await page.setViewportSize({width:390,height:844});await page.waitForTimeout(500);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.screenshot({path:root+'/previews/weekly-duet-live-mobile.png',fullPage:true});assert.deepEqual(errors,[]);console.log('Live mastery, weekly duet, rotating events, and mobile layout verified.');
}finally{await browser.close();}
