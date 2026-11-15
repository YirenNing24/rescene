// Upload a verified signed APK to R2, verify stored bytes, then switch the Worker.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const root=fileURLToPath(new URL('..',import.meta.url));
const manifest=JSON.parse(readFileSync(root+'/builds/release.json','utf8'));
const apk=root+'/builds/'+manifest.file;
if(!/^\d+\.\d+\.\d+$/.test(manifest.version)||!/^[a-f0-9]{64}$/.test(manifest.sha256))throw Error('Invalid release metadata');
if(createHash('sha256').update(readFileSync(apk)).digest('hex')!==manifest.sha256)throw Error('Local APK checksum mismatch');
const wrangler=root+'/webapp/node_modules/.bin/wrangler';
const run=args=>execFileSync(wrangler,args,{cwd:root,stdio:'inherit',timeout:300000});
const object='android/'+manifest.version+'/'+manifest.file;
run(['r2','object','put','rescene/'+object,'--file',apk,'--content-type','application/vnd.android.package-archive','--content-disposition','attachment; filename="RESCENE-Rhythm.apk"','--cache-control','public, max-age=31536000, immutable','--remote']);
const temporary=mkdtempSync(join(tmpdir(),'rescene-r2-verify-'));
try {
  const stored=join(temporary,'release.apk');
  run(['r2','object','get','rescene/'+object,'--file',stored,'--remote']);
  if(createHash('sha256').update(readFileSync(stored)).digest('hex')!==manifest.sha256)throw Error('Stored R2 APK checksum mismatch; live release unchanged');
} finally {rmSync(temporary,{recursive:true,force:true});}
run(['r2','object','put','rescene/android/'+manifest.version+'/release.json','--file',root+'/builds/release.json','--content-type','application/json','--remote']);
// Separate emulator artifacts let QA exercise the complete Android installer
// without adding x86 native libraries to the phone APK.
if(existsSync(root+'/builds/emulator-release.json')){
  const emulator=JSON.parse(readFileSync(root+'/builds/emulator-release.json','utf8'));
  if(emulator.version===manifest.version && emulator.version_code===manifest.version_code){
    const emulatorFile=root+'/builds/'+emulator.file;
    if(emulator.file!=='RESCENE-Rhythm-emulator.apk' || emulator.signing_certificate_sha256!==manifest.signing_certificate_sha256 || createHash('sha256').update(readFileSync(emulatorFile)).digest('hex')!==emulator.sha256)throw Error('Invalid emulator release');
    run(['r2','object','put','rescene/android/'+manifest.version+'/'+emulator.file,'--file',emulatorFile,'--content-type','application/vnd.android.package-archive','--remote']);
    run(['r2','object','put','rescene/android/'+manifest.version+'/emulator-release.json','--file',root+'/builds/emulator-release.json','--content-type','application/json','--remote']);
  }
}
const configPath=root+'/infra/game-api/wrangler.jsonc';
const previousConfig=readFileSync(configPath,'utf8');
const config=JSON.parse(previousConfig);config.vars.APK_OBJECT_KEY=object;
writeFileSync(configPath,JSON.stringify(config,null,2)+'\n');
try {run(['deploy','--config',configPath]);}
catch(error) {writeFileSync(configPath,previousConfig);throw error;}
const download=`https://api.remineph.online/updates/android/${manifest.version}/${manifest.file}`;
const response=await fetch(download,{headers:{Range:'bytes=0-1023','Cache-Control':'no-cache'},signal:AbortSignal.timeout(30000)});
if(response.status!==206 || response.headers.get('X-APK-Storage')!=='r2' || response.headers.get('Content-Range')!==`bytes 0-1023/${manifest.bytes}` || (await response.arrayBuffer()).byteLength!==1024)throw Error('Post-publish range verification failed');
const publicManifest={file:manifest.file,version:manifest.version,version_code:manifest.version_code,sha256:manifest.sha256,bytes:manifest.bytes,download_url:download};
writeFileSync(root+'/webapp/public/release.json',JSON.stringify(publicManifest,null,2)+'\n');
console.log('Published Android '+manifest.version+' from R2 at '+download+'; deploy the webapp to update its displayed release metadata.');
