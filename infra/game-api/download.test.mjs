import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
const bytes = new TextEncoder().encode('0123456789');
function fixture() {
  const calls = [];
  const env = {APK_OBJECT_KEY:'android/0.1.28/RESCENE-Rhythm.apk', APK_RELEASES:{
    head:async key => {calls.push(['head',key]);return {size:bytes.length,httpEtag:'"release"',uploaded:new Date('2026-11-11T00:00:00.123Z')};},
    get:async(key,options) => {calls.push(['get',key,options]);const range=options?.range;return {body:range ? bytes.slice(range.offset,range.offset+range.length) : bytes};},
  }};
  return {env,calls};
}
const request = (headers={},method='GET') => new Request('https://api.remineph.online/updates/android/0.1.28/RESCENE-Rhythm.apk',{method,headers});
test('download streams R2 without origin credentials or VPS fetch',async()=>{
  const {env,calls}=fixture();const response=await worker.fetch(request(),env);
  assert.equal(response.status,200);assert.equal(await response.text(),'0123456789');assert.equal(response.headers.get('Content-Length'),'10');
  assert.equal(response.headers.get('X-APK-Storage'),'r2');assert.match(response.headers.get('Content-Disposition'),/attachment/);assert.equal(calls.length,2);
});
test('resumed, open-ended, suffix and clamped ranges return correct bytes',async()=>{
  for(const [range,text,contentRange] of [['bytes=3-5','345','bytes 3-5/10'],['bytes=8-','89','bytes 8-9/10'],['bytes=-3','789','bytes 7-9/10'],['bytes=8-100','89','bytes 8-9/10']]) {
    const {env}=fixture();const response=await worker.fetch(request({Range:range}),env);
    assert.equal(response.status,206);assert.equal(await response.text(),text);assert.equal(response.headers.get('Content-Range'),contentRange);assert.equal(response.headers.get('Content-Length'),String(text.length));
  }
});
test('HEAD, cached release and impossible range never read the APK body',async()=>{
  for(const [req,status] of [[request({},'HEAD'),200],[request({'If-None-Match':'W/"release"'}),304],[request({Range:'bytes=10-'}),416],[request({Range:'bytes=5-2'}),416],[request({Range:'bytes=-0'}),416]]) {
    const {env,calls}=fixture();const response=await worker.fetch(req,env);assert.equal(response.status,status);assert.equal(await response.text(),'');assert.equal(calls.length,1);
  }
});
test('stale If-Range downloads the whole new release',async()=>{
  const {env}=fixture();const response=await worker.fetch(request({Range:'bytes=3-5','If-Range':'"older-release"'}),env);assert.equal(response.status,200);assert.equal(await response.text(),'0123456789');
});
test('If-Range accepts the exact Last-Modified header despite upload milliseconds',async()=>{
  const {env}=fixture();const response=await worker.fetch(request({Range:'bytes=3-5','If-Range':'Wed, 11 Nov 2026 00:00:00 GMT'}),env);assert.equal(response.status,206);assert.equal(await response.text(),'345');
});
test('missing R2 configuration fails closed instead of sending downloads to VPS',async()=>{
  assert.equal((await worker.fetch(request(),{})).status,503);assert.equal((await worker.fetch(request({},'POST'),{})).status,405);
});

test('latest download redirects to a pinned release before streaming any bytes',async()=>{
  for(const method of ['GET','HEAD']) {
    const {env,calls}=fixture();
    const response=await worker.fetch(new Request('https://api.remineph.online/download',{method}),env);
    assert.equal(response.status,307);
    assert.equal(response.headers.get('Location'),'https://api.remineph.online/updates/android/0.1.28/RESCENE-Rhythm.apk');
    assert.equal(response.headers.get('Cache-Control'),'no-store');
    assert.equal(calls.length,0);
  }
});
test('legacy mutable partial downloads restart rather than append another release',async()=>{
  const {env}=fixture();
  const response=await worker.fetch(new Request('https://api.remineph.online/download',{headers:{Range:'bytes=5-','If-Range':'"older"','If-None-Match':'"release"'}}),env);
  assert.equal(response.status,200);assert.equal(await response.text(),'0123456789');
  assert.equal(response.headers.get('Content-Range'),null);
  assert.equal(response.headers.get('Accept-Ranges'),'none');
  assert.equal(response.headers.get('Cache-Control'),'no-store');
});
test('a pinned partial download keeps the old version after the latest release changes',async()=>{
  const {env,calls}=fixture();env.APK_OBJECT_KEY='android/0.1.29/RESCENE-Rhythm.apk';
  const response=await worker.fetch(request({Range:'bytes=3-5'}),env);
  assert.equal(response.status,206);assert.equal(await response.text(),'345');
  assert.ok(calls.every(call=>call[1]==='android/0.1.28/RESCENE-Rhythm.apk'));
  assert.equal(response.headers.get('Content-Disposition'),'attachment; filename="RESCENE-Rhythm-0.1.28.apk"');
});
test('latest entry point rejects invalid configuration and unsupported methods',async()=>{
  for(const key of ['', '../../private','android/x/evil.apk']) {
    const {env}=fixture();env.APK_OBJECT_KEY=key;
    assert.equal((await worker.fetch(new Request('https://api.remineph.online/download'),env)).status,503);
  }
  assert.equal((await worker.fetch(new Request('https://api.remineph.online/download',{method:'POST'}),{})).status,405);
});
