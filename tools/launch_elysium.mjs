import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {ssh,sshOptions,cloudTarget,quote} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const root='/home/paulanthonyarriola/rescene-rhythm';
const local=root+'/contracts/launch/elysium-20261111';
const remote='/opt/fluentxverse/releases/rescene-elysium-launch-20261111';
const script='/tmp/rescene-elysium-launch';
const mode=process.argv[2];
if(mode==='stage'){
 ssh(`test ! -e ${remote}/staged.json && mkdir -p ${remote}/public`);
 execFileSync('tar',['-czf',local+'/launch.tar.gz','-C',local,'launch.mjs','assets.json','charts.json']);
 for(const [path,name] of [[local+'/launch.tar.gz','launch.tar.gz'],['/tmp/elysium-launch-operator','operator']])execFileSync('scp',[...sshOptions,path,cloudTarget+':'+remote+'/'+name],{timeout:60000});
 ssh(`tar -xzf ${remote}/launch.tar.gz -C ${remote}/public && chmod 755 ${remote}/operator && docker cp ${remote}/public budol-gmr-engine-1:${script} && docker cp ${remote}/operator budol-gmr-engine-1:/tmp/elysium-launch-operator && docker exec --user 0:0 budol-gmr-engine-1 chmod 700 ${script} /tmp/elysium-launch-operator && printf '%s' '{"staged":true}' > ${remote}/staged.json`);
 console.log('Pinned Elysium launch staged.');
}else if(mode==='run'){
 try{console.log(ssh('docker exec --user 0:0 -w /app budol-gmr-engine-1 /tmp/elysium-launch-operator --execute',{timeout:2700000,maxBuffer:4e6}));}
 catch{console.error('Launch incomplete; inspect journal and protected diagnostics before resuming.');process.exitCode=1;}
}else if(mode==='snapshot'){
 const data=ssh(`docker exec --user 0:0 budol-gmr-engine-1 cat ${script}/state-launch.json`);
 const state=JSON.parse(data);if(state.chainId!==99901||state.mode!=='launch')throw Error('Wrong launch journal');
 writeFileSync(local+'/state-launch.json',JSON.stringify(state,null,2)+'\n',{mode:0o600});
 writeFileSync(root+'/contracts/deployments/elysium-mainnet-launch.json',JSON.stringify(state,null,2)+'\n');
 ssh(`docker cp budol-gmr-engine-1:${script}/state-launch.json ${remote}/state-launch.json && chmod 600 ${remote}/state-launch.json`);
 console.log(JSON.stringify({status:state.status||'in_progress',confirmed:Object.values(state.steps).filter(x=>x.status==='confirmed').length,last:Object.keys(state.steps).at(-1),contracts:Object.keys(state.contracts)}));
}else if(mode==='error'){
 const py=`import subprocess,re,json\np=subprocess.run(['docker','exec','--user','0:0','budol-gmr-engine-1','cat','${script}/failure.private.log'],capture_output=True,text=True)\ns=p.stdout\ns=re.sub(r'https?://[^\\s)\\\"\\\']+','[redacted provider URL]',s)\ns=re.sub(r'(vaultApiKey|vaultWalletRef|rawTransaction|serializedTransaction)\\s*[:=]\\s*[^\\n]+',r'\\1: [redacted]',s)\nprint(s[-9000:])`;
 console.log(ssh('python3 -c '+quote(py)));
}else throw Error('Expected stage, run, snapshot or error');
