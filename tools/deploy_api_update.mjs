// Replace only the API container. Keep production environment, data and DB intact.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {sshOptions,cloudHost,quote} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const [release,binary]=process.argv.slice(2);
if(!/^[a-z0-9-]+$/.test(release??'')||!binary)throw Error('Expected release label and compiled API path');
const target='root@'+cloudHost,stage='/opt/remine/releases/'+release;
const remote=command=>execFileSync('ssh',[...sshOptions,target,command],{encoding:'utf8',timeout:180000});
remote('install -d -m 700 '+quote(stage));
for(const [source,name] of [[resolve(binary),'rescene-api'],[resolve('infra/game-api/Dockerfile'),'Dockerfile']])execFileSync('scp',[...sshOptions,source,target+':'+stage+'/'+name],{timeout:60000});
console.log(remote(`docker build --pull=false --network=none -t remine-api:${release} ${quote(stage)}`));
const python=`from pathlib import Path
import subprocess,shutil,re,json
stage=Path('${stage}');compose=Path('/opt/remine/compose.yaml')
old=compose.read_text();text,n=re.subn(r'image: remine-api:[^\\s]+','image: remine-api:${release}',old)
if n!=1:raise RuntimeError('Unexpected API image binding')
backup=stage/'compose.before.yaml'
if not backup.exists():shutil.copy2(compose,backup)
compose.write_text(text)
args=['docker','compose','-p','remine','-f',str(compose),'up','-d','--no-deps','--wait','--wait-timeout','120','api']
try:subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
except Exception:
 compose.write_text(old)
 subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
 raise
shutil.copy2(stage/'rescene-api',Path('/opt/remine/rescene-api'))
print(json.dumps({'healthy':True,'image':'remine-api:${release}','environmentPreserved':True}))`;
console.log(remote('python3 -c '+quote(python)));
const filename='infra/game-api/compose.yaml';
writeFileSync(filename,readFileSync(filename,'utf8').replace(/image: remine-api:[^\s]+/,'image: remine-api:'+release));
