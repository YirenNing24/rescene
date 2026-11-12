// One-time release migration. Pause the sole API writer; refuse pending shop work.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {sshOptions,cloudHost,quote} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const target='root@'+cloudHost,stage='/opt/remine/releases/card-releases-20261112';
const remote=(cmd,timeout=180000)=>execFileSync('ssh',[...sshOptions,target,cmd],{encoding:'utf8',timeout,maxBuffer:2e6});
const mode=process.argv[2];
if(mode==='stage'){
 remote('install -d -m 700 '+stage);
 for(const [source,name] of [['contracts/launch/releases-20261112/launch.mjs','launch.mjs'],['contracts/launch/releases-20261112/assets.json','assets.json'],['/tmp/rescene-release-operator','operator'],['backend/bin/rescene-api-release-cards','rescene-api'],['infra/game-api/Dockerfile','Dockerfile']])execFileSync('scp',[...sshOptions,source,target+':'+stage+'/'+name],{timeout:60000});
 console.log(remote(`docker exec --user 0:0 budol-gmr-engine-1 mkdir -p /tmp/rescene-release-cards && docker cp ${stage}/launch.mjs budol-gmr-engine-1:/tmp/rescene-release-cards/launch.mjs && docker cp ${stage}/assets.json budol-gmr-engine-1:/tmp/rescene-release-cards/assets.json && docker cp ${stage}/operator budol-gmr-engine-1:/tmp/rescene-release-operator && docker exec --user 0:0 budol-gmr-engine-1 chmod 700 /tmp/rescene-release-operator && docker build --pull=false --network=none -t remine-api:card-releases-20261112 ${stage}`));
}else if(mode==='migrate'){
 const py=`import subprocess,json
base='/opt/remine'
subprocess.run(['docker','compose','-p','remine','-f',base+'/compose.yaml','stop','api'],check=True)
q="MATCH(j:ShopOperation) WHERE j.status='pending' RETURN count(j)"
out=subprocess.check_output(['docker','exec','remine-falkordb-1','sh','-c','REDISCLI_AUTH="$REDIS_PASSWORD" exec redis-cli --json GRAPH.RO_QUERY rescene "$1"','sh',q])
result=json.loads(out)
if result[1][0][0]!=0:
 subprocess.run(['docker','compose','-p','remine','-f',base+'/compose.yaml','up','-d','api'],check=True)
 raise RuntimeError('Pending shop operations; migration aborted before chain mutation')
print(json.dumps({'soleWriterStopped':True,'pendingShopOperations':0}))`;
 console.log(remote('python3 -c '+quote(py)));
 try {console.log(remote('docker exec --user 0:0 -w /app budol-gmr-engine-1 /tmp/rescene-release-operator --execute',600000));}
 catch {console.error('Migration incomplete; preserve stopped writer and inspect protected journal.');process.exitCode=1;}
}else if(mode==='activate'){
 const state=JSON.parse(remote('docker exec --user 0:0 budol-gmr-engine-1 cat /tmp/rescene-release-cards/state-launch.json'));
 if(state.status!=='verified'||state.chainId!==99901)throw Error('Verified migration required');
 const router=state.contracts.releaseCards.address;
 writeFileSync('contracts/deployments/release-cards-elysium.json',JSON.stringify(state,null,2)+'\n');
 const py=`from pathlib import Path
import subprocess,shutil,json
base=Path('/opt/remine');stage=Path('${stage}')
env=base/'api.env';backup=stage/'api.before.env'
if not backup.exists():shutil.copy2(env,backup);backup.chmod(0o600)
lines=[line for line in env.read_text().splitlines() if not line.startswith('PULSE_CARDS_ADDRESS=') and not line.startswith('CARD_RELEASES_ENABLED=')]
lines+=['PULSE_CARDS_ADDRESS=${router}','CARD_RELEASES_ENABLED=true']
env.write_text('\\n'.join(lines)+'\\n');env.chmod(0o600)
compose=base/'compose.yaml';old=compose.read_text()
if not (stage/'compose.before.yaml').exists():shutil.copy2(compose,stage/'compose.before.yaml')
import re
text,n=re.subn(r'image: remine-api:[^\\s]+','image: remine-api:card-releases-20261112',old)
if n!=1:raise RuntimeError('Unexpected API image binding')
compose.write_text(text)
subprocess.run(['docker','compose','-p','remine','-f',str(compose),'up','-d','--no-deps','--wait','--wait-timeout','120','api'],check=True)
shutil.copy2(stage/'rescene-api',base/'rescene-api')
print(json.dumps({'router':'${router}','releaseCount':9,'cardProducts':45,'healthy':True}))`;
 console.log(remote('python3 -c '+quote(py)));
 for(const filename of ['backend/.env','backend/data/vps-deployment/api.env']){
  const lines=readFileSync(filename,'utf8').split('\n').filter(line=>!line.startsWith('PULSE_CARDS_ADDRESS=')&&!line.startsWith('CARD_RELEASES_ENABLED='));
  lines.push('PULSE_CARDS_ADDRESS='+router,'CARD_RELEASES_ENABLED=true');writeFileSync(filename,lines.join('\n'),{mode:0o600});
 }
 const compose=readFileSync('infra/game-api/compose.yaml','utf8').replace(/image: remine-api:[^\s]+/,'image: remine-api:card-releases-20261112');writeFileSync('infra/game-api/compose.yaml',compose);
}else throw Error('Expected stage, migrate or activate');
