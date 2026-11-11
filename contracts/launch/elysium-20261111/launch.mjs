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
const pc=createPublicClient({chain,transport:http(p.rpcUrl,{timeout:20000}),pollingInterval:250});
const wc=createWalletClient({account,chain,transport:http(p.rpcUrl,{timeout:20000})});
if(await pc.getChainId()!==99901)throw Error('Wrong launch chain');
const assets=JSON.parse(readFileSync(import.meta.dir+'/assets.json','utf8'));
const charts=JSON.parse(readFileSync(import.meta.dir+'/charts.json','utf8'));
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
if(!rehearsal){
 const minimum=47435318n*(await pc.getGasPrice())*101n/100n;
 if(Object.keys(state.steps).length===0 && await pc.getBalance({address:owner})<minimum)throw Error('Insufficient HYPE for rehearsed full launch');
 const wrapper=p.wrapper;
 if(!wrapper || !(await pc.getCode({address:wrapper})))throw Error('Elysium wrapper missing');
 const symbol=await pc.readContract({address:wrapper,abi:assets.ResceneStarlight.abi,functionName:'symbol'});
 const decimals=await pc.readContract({address:wrapper,abi:assets.ResceneStarlight.abi,functionName:'decimals'});
 if(symbol!=='WHYPE'||Number(decimals)!==18)throw Error('Elysium wrapper binding mismatch');
}
const unit=10n**18n;const supply=100000000n*unit;
const token=await deploy('starlight','ResceneStarlight',[owner,supply]);
const nftImpl=await deploy('erc1155Implementation','TokenERC1155');
const nftInit=encodeFunctionData({abi:assets.TokenERC1155.abi,functionName:'initialize',args:[owner,'RESCENE Collectibles','SCENE','',[],owner,owner,0n,0n,owner]});
const nft=await deploy('erc1155','TWProxy',[nftImpl,nftInit]);
let wrapper=p.wrapper;
if(rehearsal)wrapper=token; // Rehearsal marketplace uses an actual deployed ERC-20 fixture.
if(!wrapper || await pc.getCode({address:wrapper})==='0x')throw Error('Elysium native wrapper missing');
if(!rehearsal){
 const erc=assets.ResceneStarlight.abi;const symbol=await pc.readContract({address:wrapper,abi:erc,functionName:'symbol'});const decimals=await pc.readContract({address:wrapper,abi:erc,functionName:'decimals'});
 if(symbol!=='WHYPE'||Number(decimals)!==18)throw Error('Unexpected wrapped native token');
}
const extensions=[];
for(const name of ['DirectListingsLogic','EnglishAuctionsLogic','OffersLogic']){
 const implementation=await deploy(name,name,name==='OffersLogic'?[]:[wrapper]);
 extensions.push({metadata:{name,metadataURI:'',implementation},functions:assets[name].extensionFunctions.map(functionSignature=>({functionSignature,functionSelector:toFunctionSelector(functionSignature)}))});
}
const marketImpl=await deploy('marketplaceImplementation','MarketplaceV3',[{extensions,royaltyEngineAddress:zeroAddress,nativeTokenWrapper:wrapper}]);
const marketInit=encodeFunctionData({abi:assets.MarketplaceV3.abi,functionName:'initialize',args:[owner,'',[],owner,0n]});
const market=await deploy('marketplace','TWProxy',[marketImpl,marketInit]);
const board=await deploy('leaderboard','ResceneLeaderboard',[owner,owner,172800n]);
const rewards=await deploy('starlightRewards','StarlightRewards',[token,owner]);
const energy=await deploy('energyShop','EnergyDrinkShop',[owner,token,nft,market,0n,0n]);
const pulse=await deploy('pulseCards','PulseCardsLaunch',[owner,token,nft]);
const event=await deploy('eventRewards','EventRefinementRewards',[owner,nft]);
await write('approve-starlight-rewards',token,'ResceneStarlight','approve',[rewards,supply]);
const uri=x=>'data:application/json;base64,'+Buffer.from(JSON.stringify(x)).toString('base64');
const calls=[];const nftCall=(method,args)=>calls.push(encodeFunctionData({abi:assets.TokenERC1155.abi,functionName:method,args}));
const MAX=(1n<<256n)-1n;
nftCall('mintTo',[owner,MAX,uri({name:'Energy Drink',description:'Consume one to restore 5 energy, up to the 15-energy cap.',image:'https://engine.fluentxverse.com/items/energy-drink.png',attributes:[{trait_type:'Type',value:'Consumable'},{trait_type:'Energy',value:5}]}),10000n]);
for(let id=1n;id<=10n;id++){nftCall('mintTo',[owner,MAX,uri({name:'Reserved historical slot',description:'Retired non-playable ID reserved for legacy compatibility.'}),1n]);nftCall('burn',[owner,id,1n]);}
for(const [id,name,xp] of [[11n,'Refine Dust',100],[12n,'Refine Crystal',225],[13n,'Refine Prism',450]])nftCall('mintTo',[owner,MAX,uri({name,description:'Adds '+xp+' refinement XP. Failed level attempts retain XP.',attributes:[{trait_type:'Refinement XP',value:xp}]}),10000n]);
for(const address of [market,pulse,event])nftCall('setApprovalForAll',[address,true]);
for(const role of ['MINTER_ROLE','METADATA_ROLE'])nftCall('grantRole',[keccak256(toHex(role)),pulse]);
await write('configure-collection',nft,'TokenERC1155','multicall',[calls]);
const listingArgs={assetContract:nft,tokenId:0n,quantity:10000n,currency:token,pricePerToken:100n*unit,startTimestamp:BigInt(state.steps['deploy/energyShop'].blockNumber? (await pc.getBlock({blockNumber:BigInt(state.steps['deploy/energyShop'].blockNumber)})).timestamp:0),endTimestamp:2082758400n,reserved:false};
// Pin the original listing time across resumed runs.
state.listingArgs??=JSON.parse(stringify(listingArgs));save();
const la={...state.listingArgs};for(const k of ['tokenId','quantity','pricePerToken','startTimestamp','endTimestamp'])la[k]=BigInt(la[k]);
await write('create-energy-listing',market,'DirectListingsLogic','createListing',[la]);
for(let i=0;i<charts.length;i++){
 const c=charts[i];await write('register-board/'+i,board,'ResceneLeaderboard','registerBoard',[c.songId,c.difficulty,c.revision,c.units]);
}
await write('open-pulse-sales',pulse,'PulseCardsLaunch','setSalesEnabled',[true]);
if(await read(token,'ResceneStarlight','totalSupply')!==supply)throw Error('STARL supply mismatch');
if(await read(token,'ResceneStarlight','balanceOf',[owner])!==supply)throw Error('STARL treasury mismatch');
if(await read(nft,'TokenERC1155','nextTokenIdToMint')!==14n)throw Error('Collection token ID layout mismatch');
for(const id of [0n,11n,12n,13n])if(await read(nft,'TokenERC1155','balanceOf',[owner,id])!==10000n)throw Error('Inventory stock mismatch');
for(const role of ['MINTER_ROLE','METADATA_ROLE'])if(!await read(nft,'TokenERC1155','hasRole',[keccak256(toHex(role)),pulse]))throw Error('PULSE role mismatch');
for(const c of charts){const key=await read(board,'ResceneLeaderboard','boardKey',[c.songId,c.difficulty,c.revision]);const row=await read(board,'ResceneLeaderboard','boards',[key]);if(Number(row[0])!==c.units||row[2]!==true)throw Error('Registered chart mismatch');}
if(await read(pulse,'PulseCardsLaunch','INITIAL_LE_ALLOCATION')!==50n||await read(pulse,'PulseCardsLaunch','salesEnabled')!==true)throw Error('PULSE sales mismatch');
if(await read(market,'DirectListingsLogic','totalListings')!==1n)throw Error('Unexpected marketplace listings');
const listing=await read(market,'DirectListingsLogic','getListing',[0n]);if(listing.assetContract.toLowerCase()!==nft.toLowerCase()||listing.currency.toLowerCase()!==token.toLowerCase()||Number(listing.status)!==1||listing.quantity!==10000n)throw Error('Energy listing mismatch');
const gasUsed=Object.values(state.steps).reduce((n,s)=>n+BigInt(s.gasUsed||0),0n);
state.wrapper=wrapper;state.verifiedBoards=charts.length;state.gasUsed=gasUsed.toString();state.estimatedHYPEAtCurrentPrice=formatEther(gasUsed*BigInt(p.liveGasPrice||await pc.getGasPrice()));state.status='verified';state.verifiedAt=new Date().toISOString();save();
progress({status:'verified',transactions:Object.keys(state.steps).length,registeredBoards:state.verifiedBoards,gasUsed:state.gasUsed,estimatedHYPE:state.estimatedHYPEAtCurrentPrice,contracts:state.contracts});
