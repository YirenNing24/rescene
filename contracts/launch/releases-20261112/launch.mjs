import {readFileSync,writeFileSync,renameSync,existsSync,unlinkSync} from 'node:fs';
const p=await new Response(Bun.stdin.stream()).json();
const rehearsal=p.mode==='rehearse';
if(!rehearsal && (p.chainId!==99901||p.vaultProjectId!=='7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d'||p.vaultAddress.toLowerCase()!=='0x78646fedde207c4574116ac9c455b56e4091c517'))throw Error('Launch identity mismatch');
const moduleRoot=rehearsal?'/home/paulanthonyarriola/Desktop/gmr-engine/node_modules/viem/_esm':'/app/node_modules/viem/_esm';
const {createPublicClient,createWalletClient,defineChain,http,encodeDeployData,encodeFunctionData,getContractAddress,parseTransaction,keccak256,toHex,toFunctionSelector,zeroAddress,formatEther}=await import(moduleRoot+'/index.js');
const {privateKeyToAccount}=await import(moduleRoot+'/accounts/index.js');
const account=rehearsal?privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'):(await import('/app/scripts/vault-account.ts')).createVaultAccount(p);
const owner=account.address;
const chain=defineChain({id:99901,name:'Elysium Mainnet',nativeCurrency:{name:'HYPE',symbol:'HYPE',decimals:18},rpcUrls:{default:{http:[p.rpcUrl]}}});
// Public RPC fallback has low request limits. Serialize reads/broadcast checks,
// retry rate-limit replies, and preserve the signed transaction journal.
let rpcTail=Promise.resolve();
async function limitedFetch(url,options){
 const previous=rpcTail;let release;rpcTail=new Promise(resolve=>release=resolve);await previous;
 try {
  for(let attempt=0;attempt<8;attempt++){
   await Bun.sleep(650+attempt*1000);
   const response=await fetch(url,options);
   let body;try{body=await response.clone().json();}catch{}
   if(response.status!==429 && body?.error?.code!==-32017 && !/rate limit/i.test(body?.error?.message ?? ''))return response;
   if(attempt===7)return response;
  }
 } finally {release();}
}
const pc=createPublicClient({chain,transport:http(p.rpcUrl,{timeout:30000,fetchFn:limitedFetch}),pollingInterval:2000});
const wc=createWalletClient({account,chain,transport:http(p.rpcUrl,{timeout:20000})});
if(await pc.getChainId()!==99901)throw Error('Wrong launch chain');
const assets=JSON.parse(readFileSync(import.meta.dir+'/assets.json','utf8'));

const path=import.meta.dir+'/state-'+p.mode+'.json';
const state=existsSync(path)?JSON.parse(readFileSync(path,'utf8')):{chainId:99901,mode:p.mode,owner,contracts:{},steps:{},startedAt:new Date().toISOString()};
if(state.owner.toLowerCase()!==owner.toLowerCase()||state.chainId!==99901||state.mode!==p.mode)throw Error('Journal identity mismatch');
const stringify=v=>JSON.stringify(v,(_,x)=>typeof x==='bigint'?x.toString():x,2);
function save(){writeFileSync(path+'.tmp',stringify(state)+'\n',{mode:0o600});renameSync(path+'.tmp',path);}
function progress(v){console.log(JSON.stringify(v,(_,x)=>typeof x==='bigint'?x.toString():x));}
async function send(key,to,data){
 const inputHash=keccak256(data);let s=state.steps[key];
 if(s && (s.to!==to||s.inputHash!==inputHash))throw Error('Recorded request mismatch: '+key);
 if(!s){
  const confirmed=Object.values(state.steps).filter(x=>x.status==='confirmed');
  const expected=confirmed.length?Math.max(...confirmed.map(x=>x.nonce))+1:null;
  let nonce,latest;
  for(let attempt=0;attempt<40;attempt++){
   nonce=await pc.getTransactionCount({address:owner,blockTag:'pending'});
   latest=await pc.getTransactionCount({address:owner,blockTag:'latest'});
   if(nonce===latest && (expected===null||nonce===expected))break;
   if(attempt===39)throw Error('Wallet nonce has not settled; preserve journal');
   await Bun.sleep(500);
  }
  const quoted=await pc.getGasPrice();const price=quoted+5000000n>510000000n?quoted+5000000n:510000000n;const estimate=await pc.estimateGas({account:owner,to,data});const gas=estimate*120n/100n+20000n;
  const balance=await pc.getBalance({address:owner});if(balance<gas*price)throw Error('Insufficient HYPE before '+key);
  const raw=await account.signTransaction({chainId:99901,nonce,gas,gasPrice:price,data,...(to?{to}:{}),value:0n,type:'legacy'});
  s=state.steps[key]={to,inputHash,nonce,hash:keccak256(raw),status:'prepared',...(to?{}:{contractAddress:getContractAddress({from:owner,nonce:BigInt(nonce)})})};
  writeFileSync(import.meta.dir+'/'+s.hash+'.raw',raw,{mode:0o600,flag:'wx'});save();
 }
 if(s.status==='confirmed'){
  const r=await pc.getTransactionReceipt({hash:s.hash});if(r.status!=='success'||r.blockHash!==s.blockHash)throw Error('Recorded receipt changed: '+key);return s;
 }
 let receipt;try{receipt=await pc.getTransactionReceipt({hash:s.hash});}catch{}
 if(!receipt){
  let raw=readFileSync(import.meta.dir+'/'+s.hash+'.raw','utf8');
  for(let attempt=0;attempt<6;attempt++){
   try{await pc.sendRawTransaction({serializedTransaction:raw});break;}
   catch(error){
    let known=false;try{await pc.getTransaction({hash:s.hash});known=true;}catch{}
    if(known)break;
    if(String(error.details||'').includes('max fee per gas less than block base fee')){
     const latest=await pc.getTransactionCount({address:owner,blockTag:'latest'});
     if(latest>s.nonce)throw Error('Nonce consumed; inspect previous transaction receipts');
     const parsed=parseTransaction(raw);const quote=await pc.getGasPrice();const price=quote+5000000n>510000000n?quote+5000000n:510000000n;
     raw=await account.signTransaction({chainId:99901,nonce:s.nonce,gas:parsed.gas,gasPrice:price,data,...(to?{to}:{}),value:0n,type:'legacy'});
     s.previousHashes??=[];s.previousHashes.push(s.hash);s.hash=keccak256(raw);
     writeFileSync(import.meta.dir+'/'+s.hash+'.raw',raw,{mode:0o600});save();
    }
    if(attempt===5)throw Error('Broadcast uncertain; retain journal for '+key);
    await Bun.sleep(1500);
   }
  }
  s.status='submitted';save();
  receipt=await pc.waitForTransactionReceipt({hash:s.hash,timeout:180000});
 }
 if(receipt.status!=='success'){s.status='reverted';save();throw Error('Launch transaction reverted: '+key+' '+s.hash);}
 if(!to && receipt.contractAddress?.toLowerCase()!==s.contractAddress.toLowerCase())throw Error('Unexpected deployed address');
 Object.assign(s,{status:'confirmed',blockHash:receipt.blockHash,blockNumber:receipt.blockNumber.toString(),gasUsed:receipt.gasUsed.toString(),effectiveGasPrice:receipt.effectiveGasPrice.toString()});save();
 if(existsSync(import.meta.dir+'/'+s.hash+'.raw'))unlinkSync(import.meta.dir+'/'+s.hash+'.raw');
 progress({step:key,status:s.status,hash:s.hash,...(!to?{address:s.contractAddress}:{}),gasUsed:s.gasUsed});return s;
}
async function deploy(key,name,args=[]){const a=assets[name];const data=encodeDeployData({abi:a.abi,bytecode:a.bytecode,args});const s=await send('deploy/'+key,undefined,data);state.contracts[key]={address:s.contractAddress,transactionHash:s.hash,blockNumber:s.blockNumber,artifact:name};save();return s.contractAddress;}
async function write(key,address,name,method,args){return send(key,address,encodeFunctionData({abi:assets[name].abi,functionName:method,args}));}
async function read(address,name,method,args=[]){return pc.readContract({address,abi:assets[name].abi,functionName:method,args});}

const previous=assets.bindings;
const token=previous.starlight, nft=previous.collection, old=previous.pulse;
if(await read(old,'PulseCards','salesEnabled')) await write('close-legacy-sales',old,'PulseCards','setSalesEnabled',[false]);
const router=await deploy('releaseCards','ReleaseCards',[owner,token,nft,old]);
const minter=keccak256(toHex('MINTER_ROLE')),metadata=keccak256(toHex('METADATA_ROLE'));
for(const [role,label] of [[minter,'minter'],[metadata,'metadata']]) {
 await write('grant-'+label,nft,'TokenERC1155','grantRole',[role,router]);
}
await write('approve-materials',nft,'TokenERC1155','setApprovalForAll',[router,true]);
const count=Number(await read(old,'PulseCards','count'));
if(count>10000)throw Error('Unexpected legacy count; manual paging audit needed');
state.legacyCount??=count;if(state.legacyCount!==count)throw Error('Legacy registry changed during migration');save();
if(count>0){
 const ids=await read(old,'PulseCards','tokenIds',[0n,BigInt(count)]);
 // The current rollout has no cards; if that changes, resolve every holder from
 // canonical TransferSingle/TransferBatch logs before doing any import writes.
 if(!assets.legacyOwners || ids.some(id=>!assets.legacyOwners[id.toString()]))throw Error('Legacy ownership snapshot required; sales remain closed');
 for(let i=0;i<ids.length;i+=20){const batch=ids.slice(i,i+20);await write('import/'+i,router,'ReleaseCards','importLegacy',[batch,batch.map(id=>assets.legacyOwners[id.toString()])]);}
}
await write('finish-migration',router,'ReleaseCards','finishMigration',[]);
if(await read(router,'ReleaseCards','count')!==BigInt(count))throw Error('Migration count mismatch');
for(let member=0;member<5;member++)if(await read(router,'ReleaseCards','initialLESold',[BigInt(member)])!==await read(old,'PulseCards','initialLESold',[BigInt(member)]))throw Error('PULSE allocation changed');
for(const [role,label] of [[minter,'minter'],[metadata,'metadata']]) await write('revoke-legacy-'+label,nft,'TokenERC1155','revokeRole',[role,old]);
await write('revoke-legacy-materials',nft,'TokenERC1155','setApprovalForAll',[old,false]);
await write('open-release-sales',router,'ReleaseCards','setSalesEnabled',[true]);
if(await read(router,'ReleaseCards','RELEASE_COUNT')!==9n || !await read(router,'ReleaseCards','salesEnabled'))throw Error('Release verification failed');
for(let member=5;member<45;member++)if(await read(router,'ReleaseCards','initialLESold',[BigInt(member)])!==0n)throw Error('New allocation not empty');
state.status='verified';state.verifiedAt=new Date().toISOString();save();progress({status:'verified',router,count,releaseCount:9,products:45});
