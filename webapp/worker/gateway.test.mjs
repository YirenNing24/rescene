import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker, {SessionVault,allowed} from './index.ts';
const origin='https://rhythm.remineph.online';
function fixture(handler){
 const objects=new Map(),requests=[];
 const env={API_ORIGIN:'https://api.remineph.online',ASSETS:{fetch:async()=>new Response('<html>backstage</html>',{headers:{'Content-Type':'text/html'}})},GAME_API:{fetch:async request=>{requests.push(request);return handler(request);}},SESSIONS:{idFromName:n=>n,get:id=>{if(!objects.has(id)){const values=new Map();let alarm;const ctx={storage:{get:async k=>structuredClone(values.get(k)),put:async(k,v)=>values.set(k,structuredClone(v)),deleteAll:async()=>values.clear(),setAlarm:async t=>{alarm=t;}}};objects.set(id,{vault:new SessionVault(ctx,env),values,alarm});}return objects.get(id).vault;}}};
 return {env,objects,requests};
}
const loginData={access_token:'secret-access',refresh_token:'secret-refresh',expires_in:3600,refresh_expires_at:Math.floor(Date.now()/1000)+2592000,user:{id:'a'.repeat(32),username:'test'}};
const req=(path,method='GET',body,cookie)=>new Request(origin+'/api'+path,{method,headers:{Origin:origin,'Content-Type':'application/json',...(cookie?{Cookie:cookie}:{}),'CF-Connecting-IP':'203.0.113.5'},body:body?JSON.stringify(body):undefined});
async function login(f){const res=await worker.fetch(req('/auth/login','POST',{username:'test',password:'private'}),f.env);assert.equal(res.status,200);return res;}
test('gameplay is blocked, account routes are explicitly allowed',()=>{
 for(const path of ['/runs','/runs/'+ 'a'.repeat(32)+'/complete','/auth/refresh','/api/admin/v1/players','//evil.test','/wallet/provision'])assert.equal(allowed('POST',path),false,path);
 assert.equal(allowed('POST','/events/pulse_first_scene_2026/missions/opening/claim'),true);assert.equal(allowed('POST','/events/weekly_2026-11-09/missions/weekly_clears/claim'),true);assert.equal(allowed('POST','/mastery/38c9a4926480/easy/claim'),true);assert.equal(allowed('POST','/coop/'+'a'.repeat(32)+'/claim'),true);assert.equal(allowed('POST','/events/../../missions/opening/claim'),false);assert.equal(allowed('POST','/collection/action'),true);assert.equal(allowed('GET','/inventory'),true);assert.equal(allowed('DELETE','/profile/media/gallery/'+'a'.repeat(32)),true);
});
test('login only returns public user data and uses a secure 30-day cookie',async()=>{
 const f=fixture(async()=>Response.json(loginData));const res=await login(f);assert.deepEqual(await res.json(),{user:loginData.user});
 const cookie=res.headers.get('Set-Cookie');assert.match(cookie,/^__Host-rhythm=[a-f0-9]{64}; Path=\/; HttpOnly; Secure; SameSite=Strict; Max-Age=2592000$/);
 assert.equal(f.requests[0].headers.get('CF-Connecting-IP'),'203.0.113.5');assert.equal(f.requests[0].headers.has('Cookie'),false);
});
test('cross-origin posts fail before upstream access; GETs cannot mutate logout',async()=>{
 const f=fixture(async()=>{throw Error('must not reach origin');});const forged=new Request(origin+'/api/auth/login',{method:'POST',headers:{Origin:'https://evil.test'},body:'{}'});
 assert.equal((await worker.fetch(forged,f.env)).status,403);assert.equal((await worker.fetch(req('/logout'),f.env)).status,405);assert.equal(f.requests.length,0);
});
test('authenticated proxy attaches stored access token, strips arbitrary browser auth',async()=>{
 const f=fixture(async r=>r.url.endsWith('/login')?Response.json(loginData):Response.json({items:[]}));const loginRes=await login(f);const cookie=loginRes.headers.get('Set-Cookie').split(';')[0];
 const request=req('/inventory','GET',undefined,cookie);request.headers.set('Authorization','Bearer forged');request.headers.set('X-Admin-Signature','forged');
 const res=await worker.fetch(request,f.env);assert.equal(res.status,200);const sent=f.requests.at(-1);assert.equal(sent.headers.get('Authorization'),'Bearer secret-access');assert.equal(sent.headers.has('X-Admin-Signature'),false);assert.equal(sent.headers.has('Cookie'),false);
 assert.match(res.headers.get('Content-Security-Policy'),/media-src 'none'/);
});
test('concurrent expired requests rotate refresh token exactly once',async()=>{
 let rotations=0;const f=fixture(async r=>{if(r.url.endsWith('/login'))return Response.json({...loginData,expires_in:0});if(r.url.endsWith('/refresh')){rotations++;const body=await r.json();assert.match(body.request_id,/^[a-f0-9]{32}$/);await new Promise(resolve=>setTimeout(resolve,10));return Response.json({...loginData,access_token:'rotated-access',refresh_token:'rotated-refresh'});}assert.equal(r.headers.get('Authorization'),'Bearer rotated-access');return Response.json({ok:true});});
 const cookie=(await login(f)).headers.get('Set-Cookie').split(';')[0];const results=await Promise.all([worker.fetch(req('/inventory','GET',undefined,cookie),f.env),worker.fetch(req('/progression','GET',undefined,cookie),f.env)]);assert.ok(results.every(r=>r.status===200));assert.equal(rotations,1);
});
test('lost rotation response retries the same durable request ID',async()=>{
 const ids=[];const f=fixture(async r=>{if(r.url.endsWith('/login'))return Response.json({...loginData,expires_in:0});if(r.url.endsWith('/refresh')){const b=await r.json();ids.push(b.request_id);if(ids.length===1)throw Error('connection lost');return Response.json(loginData);}return Response.json({ok:true});});
 const cookie=(await login(f)).headers.get('Set-Cookie').split(';')[0];assert.equal((await worker.fetch(req('/session','GET',undefined,cookie),f.env)).status,503);assert.equal((await worker.fetch(req('/session','GET',undefined,cookie),f.env)).status,200);assert.equal(ids.length,2);assert.equal(ids[0],ids[1]);
});
test('logout revokes server refresh and clears local durable state and cookie',async()=>{
 const f=fixture(async r=>r.url.endsWith('/login')?Response.json(loginData):Response.json({ok:true}));const cookie=(await login(f)).headers.get('Set-Cookie').split(';')[0];const res=await worker.fetch(req('/logout','POST',{},cookie),f.env);assert.equal(res.status,200);assert.match(res.headers.get('Set-Cookie'),/Max-Age=0/);assert.equal((await worker.fetch(req('/session','GET',undefined,cookie),f.env)).status,401);assert.equal((await f.requests.at(-1).json()).refresh_token,'secret-refresh');
});
test('APK uses the existing public download and static pages have security headers',async()=>{
 const f=fixture(async()=>Response.json({}));const download=await worker.fetch(new Request(origin+'/download'),f.env);assert.equal(download.status,302);assert.equal(download.headers.get('Location'),'https://api.remineph.online/download');const page=await worker.fetch(new Request(origin+'/'),f.env);assert.equal(page.headers.get('X-Frame-Options'),'DENY');assert.equal(page.headers.get('Cache-Control'),'no-cache');
});
