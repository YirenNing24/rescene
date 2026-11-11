import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import worker from './index.ts';

const secret='isolated-worker-test-secret-'.repeat(3);
const email='owner@example.test';
function token(){const h=Buffer.from('{"alg":"HS256"}').toString('base64url'),p=Buffer.from(JSON.stringify({sub:email,aud:'remine-admin-gateway',exp:Math.floor(Date.now()/1000)+60})).toString('base64url');return h+'.'+p+'.'+createHmac('sha256',secret).update(h+'.'+p).digest('base64url')}
const env={ADMIN_GATEWAY_SECRET:secret,API_ORIGIN:'https://api.remineph.online',ADMIN_ORIGIN_CONFIG:{get(){throw Error('Retired desktop KV must not be read')},put(){throw Error('Retired desktop KV must not be written')}}};

test('signed admin traffic uses the VPS and preserves the backend proof',async t=>{
 let sent;
 t.mock.method(globalThis,'fetch',async(url,options)=>{sent={url:String(url),options};return Response.json({rows:[]})});
 const response=await worker.fetch(new Request('https://admin.remineph.online/api/players?q=example&offset=50',{headers:{Cookie:`__Host-remine_admin_auth=${token()}; __Host-remine_admin_step=fixture-mfa`}}),env);
 assert.equal(response.status,200);assert.equal(sent.url,'https://api.remineph.online/api/admin/v1/players?q=example&offset=50');
 const headers=sent.options.headers;
 const bodyDigest=Buffer.from(await crypto.subtle.digest('SHA-256',new Uint8Array())).toString('hex');
 const proof=['GET','/api/admin/v1/players?q=example&offset=50',email,headers.get('X-Admin-Time'),headers.get('X-Admin-Nonce'),bodyDigest].join('\n');
 assert.equal(headers.get('X-Admin-Signature'),createHmac('sha256',secret).update(proof).digest('hex'));
 assert.equal(headers.get('Cookie'),'__Host-remine_admin_step=fixture-mfa');assert.equal(response.headers.get('Cache-Control'),'no-store');
});

test('a valid old desktop registration cannot change the origin',async()=>{
 const origin='https://retired-desktop.trycloudflare.com',ts=String(Math.floor(Date.now()/1000));
 const signature=createHmac('sha256',secret).update(`origin\n${ts}\n${origin}`).digest('hex');
 const r=await worker.fetch(new Request('https://admin.remineph.online/internal/origin',{method:'POST',headers:{'X-Origin-Time':ts,'X-Origin-Signature':signature},body:origin}),env);
 assert.equal(r.status,404);assert.equal((await r.json()).error.code,'not_found');
});
