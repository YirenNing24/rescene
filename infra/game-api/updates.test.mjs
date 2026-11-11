import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import {updateObject} from './updates.js';
const release={version:'0.1.6',version_code:7,bytes:194000000,sha256:'a'.repeat(64),signing_certificate_sha256:'b'.repeat(64),release_notes:'In-app updates.',private_field:'must not leave the server'};
function fixture(data=release){return {APK_OBJECT_KEY:'android/0.1.6/RESCENE-Rhythm.apk',APK_RELEASES:{get:async key=>{assert.equal(key,'android/0.1.6/release.json');return {body:true,size:1024,json:async()=>data};}}};}
test('public release metadata comes from R2 without VPS access or authentication',async()=>{
 const response=await worker.fetch(new Request('https://api.remineph.online/updates/android.json'),fixture());assert.equal(response.status,200);const data=await response.json();assert.equal(data.version_code,7);assert.equal(data.download_url,'https://api.remineph.online/updates/android/0.1.6/RESCENE-Rhythm.apk');assert.equal(data.private_field,undefined);assert.equal(response.headers.get('Cache-Control'),'no-store');
});
test('update metadata rejects corrupt or mismatched distribution data',async()=>{
 for(const data of [{...release,sha256:'bad'},{...release,bytes:-1},{...release,bytes:2147483648},{...release,version_code:7.5},{...release,version:'../../secret'},{...release,version:'0.1.5'}])assert.equal((await worker.fetch(new Request('https://api.remineph.online/updates/android.json'),fixture(data))).status,503);
});
test('only narrowly scoped immutable APK paths can read R2 release objects',()=>{
 assert.equal(updateObject('/updates/android/0.1.6/RESCENE-Rhythm.apk'),'android/0.1.6/RESCENE-Rhythm.apk');
 assert.equal(updateObject('/updates/android/0.1.6/RESCENE-Rhythm-emulator.apk'),'android/0.1.6/RESCENE-Rhythm-emulator.apk');
 for(const path of ['/updates/android/../../secret','/updates/android/0.1.6/release.json','/updates/android/0.1.6/evil.apk','/updates/android/x/RESCENE-Rhythm.apk'])assert.equal(updateObject(path),null);
});
test('emulator updates have their own artifact and never add x86 code to phone downloads',async()=>{
 const env={APK_OBJECT_KEY:'android/0.1.6/RESCENE-Rhythm.apk',APK_RELEASES:{get:async key=>{assert.equal(key,'android/0.1.6/emulator-release.json');return {body:true,size:1024,json:async()=>({...release,file:'RESCENE-Rhythm-emulator.apk',architectures:['x86_64']})};}}};
 const response=await worker.fetch(new Request('https://api.remineph.online/updates/android.json?arch=x86_64'),env);assert.equal(response.status,200);assert.equal((await response.json()).download_url,'https://api.remineph.online/updates/android/0.1.6/RESCENE-Rhythm-emulator.apk');
 assert.equal((await worker.fetch(new Request('https://api.remineph.online/updates/android.json?arch=../../private'),env)).status,400);
});
test('HEAD and unsupported methods never expose update bodies',async()=>{
 const head=await worker.fetch(new Request('https://api.remineph.online/updates/android.json',{method:'HEAD'}),fixture());assert.equal(head.status,200);assert.equal(await head.text(),'');
 assert.equal((await worker.fetch(new Request('https://api.remineph.online/updates/android.json',{method:'POST'}),fixture())).status,405);
});
