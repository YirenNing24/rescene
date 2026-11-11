import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {ssh,sshOptions,cloudTarget} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const root='/home/paulanthonyarriola/rescene-rhythm';
const listings=JSON.parse(readFileSync(root+'/contracts/deployments/member-card-listings.json'));
if(listings.status!=='confirmed'||listings.cards.length!==5)throw Error('Five confirmed card listings required');
const artifact=JSON.parse(readFileSync(root+'/contracts/out/PulseCards.sol/PulseCardsLaunch.json'));
const receiptFile=root+'/contracts/deployments/pulse-cards-launch-v3.json';
const request={projectId:'7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d',chainId:421614,treasury:'0x78646fedde207c4574116ac9c455b56e4091c517',token:'0xea99194cb96917672973eb55350c667c68c04c20',abi:artifact.abi,bytecode:artifact.bytecode.object,guardFile:'/tmp/rescene-pulse-cards-launch-v3.json',collection:'0xa468d30613fe78692f857f55326a069b157c8b56',market:'0xa3d343ea5bb4c2242b5214588886e9d3c52e0c57',itemId:'1',listingId:'1'};
try{readFileSync(receiptFile);throw Error('Local launch record exists; inspect it before any repeat');}catch(e){if(e.code!=='ENOENT')throw e;}
writeFileSync(receiptFile,JSON.stringify({state:'prepared',request},null,2));
execFileSync('scp',[...sshOptions,'/tmp/rescene-pulse-operator',cloudTarget+':/tmp/rescene-pulse-operator'],{timeout:30000});
ssh('docker cp /tmp/rescene-pulse-operator budol-gmr-engine-1:/tmp/rescene-pulse-operator');
writeFileSync(receiptFile,JSON.stringify({state:'submitted-or-uncertain',request},null,2));
const output=ssh('docker exec -i -w /app budol-gmr-engine-1 /tmp/rescene-pulse-operator',{input:JSON.stringify(request),timeout:120000});
const result=JSON.parse(output);if(result.status!=='success')throw Error('Deployment not confirmed');
writeFileSync(receiptFile,JSON.stringify({state:'confirmed',request,receipt:result},null,2)+'\n');console.log(JSON.stringify(result));
