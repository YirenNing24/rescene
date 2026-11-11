// One-time testnet deployment; the Engine signer remains in Vault.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {ssh,sshOptions,cloudTarget} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const root='/home/paulanthonyarriola/rescene-rhythm';
const file=root+'/contracts/deployments/pulse-event-rewards-2026.json';
try{readFileSync(file);throw Error('A deployment record already exists; inspect it before retrying.');}catch(e){if(e.code!=='ENOENT')throw e;}
const artifact=JSON.parse(readFileSync(root+'/contracts/out/EventRefinementRewards.sol/EventRefinementRewards.json','utf8'));
const request={projectId:'7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d',chainId:421614,treasury:'0x78646fedde207c4574116ac9c455b56e4091c517',token:'0xa468d30613fe78692f857f55326a069b157c8b56',abi:artifact.abi,bytecode:artifact.bytecode.object,guardFile:'/tmp/rescene-event-refinement-rewards-2026.json'};
writeFileSync(file,JSON.stringify({state:'prepared',request},null,2)+'\n');
execFileSync('scp',[...sshOptions,'/tmp/rescene-event-operator',cloudTarget+':/tmp/rescene-event-operator'],{timeout:30000});
ssh('docker cp /tmp/rescene-event-operator budol-gmr-engine-1:/tmp/rescene-event-operator');
writeFileSync(file,JSON.stringify({state:'submitted-or-uncertain',request},null,2)+'\n');
const output=ssh('docker exec -i -w /app budol-gmr-engine-1 /tmp/rescene-event-operator',{input:JSON.stringify(request),timeout:120000});
const result=JSON.parse(output);if(result.status!=='success')throw Error('Deployment not confirmed');
writeFileSync(file,JSON.stringify({state:'confirmed',request,receipt:result},null,2)+'\n');console.log(JSON.stringify(result));
