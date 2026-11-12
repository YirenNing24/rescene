// Repair only the Elysium provider binding; preserve every other chain and secret.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {sshOptions,cloudHost,quote} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const remote=command=>execFileSync('ssh',[...sshOptions,'root@'+cloudHost,command],{encoding:'utf8',timeout:180000});
const rpc='https://rpc.elysium.kinetiq.xyz';
const py=`import json,subprocess,urllib.request,shutil,time
from pathlib import Path
rpc='${rpc}'
def call(method,params):
 req=urllib.request.Request(rpc,data=json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode(),headers={'Content-Type':'application/json','User-Agent':'RESCENE-Rhythm-Backend/0.1'})
 with urllib.request.urlopen(req,timeout=15) as r:d=json.load(r)
 if 'error' in d:raise RuntimeError('Public RPC rejected '+method)
 return d['result']
if int(call('eth_chainId',[]),16)!=99901:raise RuntimeError('Wrong backup chain')
balance=int(call('eth_getBalance',['0x78646fedde207c4574116ac9c455b56e4091c517','latest']),16)
engine=json.loads(subprocess.check_output(['docker','inspect','budol-gmr-engine-1']))[0]
files=engine['Config']['Labels']['com.docker.compose.project.config_files'].split(',')
override=Path(files[-1]);data=json.loads(override.read_text())
env=data['services']['gmr-engine']['environment']
mapping=json.loads(env['GMR_ENGINE_CHAIN_RPC_URLS'])
mapping['99901']=rpc
env['GMR_ENGINE_CHAIN_RPC_URLS']=json.dumps(mapping,separators=(',',':'))
env['GMR_ENGINE_ELYSIUM_MAINNET_RPC_URL']=rpc
backup=override.with_name('engine.before-rpc-repair-20261112.private.json')
if not backup.exists():shutil.copy2(override,backup);backup.chmod(0o600)
override.write_text(json.dumps(data,indent=2)+'\\n');override.chmod(0o600)
args=['docker','compose','-p',engine['Config']['Labels']['com.docker.compose.project']]
for f in files:args+=['-f',f]
args+=['up','-d','--no-deps','gmr-engine']
subprocess.run(args,check=True,stdout=subprocess.DEVNULL)
api=Path('/opt/remine/api.env');old=api.read_text()
backup=Path('/opt/remine/backups/api.before-rpc-repair-20261112.env')
if not backup.exists():shutil.copy2(api,backup);backup.chmod(0o600)
lines=old.splitlines()
keys=['STARLIGHT_RPC_URL','LEADERBOARD_RPC_URL']
lines=[line for line in lines if not any(line.startswith(k+'=') for k in keys)]
lines += [k+'='+rpc for k in keys]
api.write_text('\\n'.join(lines)+'\\n');api.chmod(0o600)
subprocess.run(['docker','compose','-p','remine','-f','/opt/remine/compose.yaml','up','-d','--no-deps','--wait','--wait-timeout','120','api'],check=True,stdout=subprocess.DEVNULL)
for _ in range(60):
 c=json.loads(subprocess.check_output(['docker','inspect','budol-gmr-engine-1']))[0]
 if c['State'].get('Health',{}).get('Status')=='healthy':break
 time.sleep(1)
else:raise RuntimeError('Engine did not become healthy')
print(json.dumps({'chainId':99901,'treasuryBalanceWei':str(balance),'engineHealthy':True,'gameApiHealthy':True,'rpc':rpc}))`;
console.log(remote('python3 -c '+quote(py)));
// Keep private local deployment files aligned without revealing credentials.
for(const filename of ['backend/.env','backend/data/vps-deployment/api.env']){
 const data=readFileSync(filename,'utf8');
 const updated=data.replace(/^(STARLIGHT_RPC_URL|LEADERBOARD_RPC_URL)=.*$/gm,(_,key)=>key+'='+rpc);
 writeFileSync(filename,updated,{mode:0o600});
}
