import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,existsSync,chmodSync,mkdirSync} from 'node:fs';
import {sshOptions,cloudHost,quote} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const root='/home/paulanthonyarriola/rescene-rhythm';
const target='root@'+cloudHost,stage='/opt/remine/releases/elysium-20261111';
const remote=(command,opts={})=>execFileSync('ssh',[...sshOptions,target,command],{encoding:'utf8',timeout:180000,maxBuffer:4e6,...opts});
const mode=process.argv[2];
if(mode==='prepare'){
 const state=JSON.parse(readFileSync(root+'/contracts/launch/elysium-20261111/state-launch.json'));
 if(state.status!=='verified'||state.verifiedBoards!==128)throw Error('Verified mainnet launch required');
 const manifest={chainId:99901,network:'Elysium Mainnet',nativeCurrency:'HYPE',engineProjectId:'7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d',engineProject:'rescene-rhythm',adminAddress:state.owner,publisherAddress:state.owner,nativeTokenWrapperAddress:state.wrapper,thirdwebCommit:'0da770f27209774061e118401e8b9796ead97ced',contracts:state.contracts,leaderboardRegisteredBoards:state.verifiedBoards,starlight:{name:'RESCENE Starlight',symbol:'STARL',decimals:18,initialSupply:'100000000'},energyDrink:{tokenId:0,listingId:0,stock:10000,priceSTARL:100,energy:5},refinementMaterials:[{tokenId:11,stock:10000},{tokenId:12,stock:10000},{tokenId:13,stock:10000}],pulseInitialAllocationPerMember:50,legacyFirstSceneShopExcluded:true,gasUsed:state.gasUsed,verifiedAt:state.verifiedAt};
 writeFileSync(root+'/contracts/deployments/elysium-mainnet.json',JSON.stringify(manifest,null,2)+'\n');
 remote('install -d -m 755 '+stage);
 for(const [file,name] of [[root+'/backend/bin/rescene-api-elysium','rescene-api'],[root+'/infra/game-api/Dockerfile','Dockerfile'],[root+'/contracts/launch/elysium-20261111/state-launch.json','state-launch.json'],['/tmp/rescene-elysium-cutover.py','cutover.py']])execFileSync('scp',[...sshOptions,file,target+':'+stage+'/'+name],{timeout:60000});
 console.log(remote('python3 '+stage+'/cutover.py stage'));
}else if(['activate','verify'].includes(mode)){
 const report=remote('python3 '+stage+'/cutover.py '+mode);console.log(report);
 if(mode==='activate')writeFileSync(root+'/contracts/deployments/elysium-cutover.json',JSON.stringify(JSON.parse(report.trim().split('\n').at(-1)),null,2)+'\n');
}else if(mode==='sync-local'){
 // Capture private environment data in memory only, retaining local database settings.
 const env=remote('cat /opt/remine/api.env');
 writeFileSync(root+'/backend/data/vps-deployment/api.env',env,{mode:0o600});chmodSync(root+'/backend/data/vps-deployment/api.env',0o600);
 const keys=['LEADERBOARD_ENABLED','LEADERBOARD_CHAIN_ID','LEADERBOARD_ADDRESS','LEADERBOARD_PUBLISHER','LEADERBOARD_RPC_URL','LEADERBOARD_START_BLOCK','STARLIGHT_ENABLED','STARLIGHT_CHAIN_ID','STARLIGHT_TOKEN_ADDRESS','STARLIGHT_DISTRIBUTOR_ADDRESS','STARLIGHT_TREASURY_ADDRESS','STARLIGHT_RPC_URL','MARKETPLACE_ENABLED','MARKETPLACE_CHAIN_ID','MARKETPLACE_ADDRESS','MARKETPLACE_COLLECTION_ADDRESS','SHOP_ENABLED','SHOP_ROUTER_ADDRESS','SHOP_TOKEN_ID','SHOP_LISTING_ID','CARDS_ENABLED','CARDS_ROUTER_ADDRESS','PULSE_CARDS_ADDRESS','EVENT_REWARD_ROUTER_ADDRESS','LEGACY_CARDS_ROUTER_ADDRESS'];
 const values=Object.fromEntries(env.split('\n').filter(x=>x.includes('=')).map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1)];}).filter(([k])=>keys.includes(k)));
 const file=root+'/backend/.env';const old=readFileSync(file,'utf8');const next=old.split('\n').filter(line=>!keys.some(key=>line.startsWith(key+'=')||line.startsWith('export '+key+'=')));
 const shellQuote=v=>"'"+v.replaceAll("'","'\\''")+"'";
 next.push('# Elysium mainnet launch configuration.',...Object.entries(values).map(([k,v])=>k+'='+shellQuote(v)));
 writeFileSync(file,next.join('\n')+'\n',{mode:0o600});chmodSync(file,0o600);
 console.log('Private launch configuration synchronized; local database URL preserved.');
}else throw Error('Expected prepare, activate, verify or sync-local');
