#!/usr/bin/env python3
"""Operator: launch one real item/listing via Engine. Durable IDs prevent blind retries.
Never repeat a submission with an uncertain response without inspecting Engine/chain.
"""
import json, time, urllib.request, urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
env={}
for line in (ROOT/'backend/.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        key,value=line.split('=',1);env[key]=value.strip().strip('"').strip("'")
BASE=env['ENGINE_BASE_URL']
HEAD={'Content-Type':'application/json','X-GMR-Engine-Key':env['ENGINE_API_KEY'],'User-Agent':'Mozilla/5.0'}
MANIFEST=json.loads((ROOT/'contracts/deployments/arbitrum-sepolia.json').read_text())
COLLECTION=MANIFEST['erc1155']['address'];MARKET=MANIFEST['marketplace']['address'];TOKEN=MANIFEST['starlight']['address'];TREASURY=MANIFEST['adminAddress']
RECORD=ROOT/'contracts/deployments/energy-drink-listing.json'
state=json.loads(RECORD.read_text()) if RECORD.exists() else {'steps':{}}
def save(): RECORD.write_text(json.dumps(state,indent=2)+'\n')
def call(path,body=None,headers=None):
    req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,headers=headers or HEAD)
    with urllib.request.urlopen(req,timeout=25) as response:return json.load(response)
def artifact(name):return json.loads((Path('/home/paulanthonyarriola/Desktop/gmr-engine/gmr-engine/internal/contracts/prebuilt')/(name+'.json')).read_text())['abi']
NFT=artifact('TokenERC1155');LIST=artifact('DirectListingsLogic')
def function(abi,name):return [next(x for x in abi if x.get('type')=='function' and x.get('name')==name)]
def read(address,name,args,abi):return call('/v1/contracts/read',{'chainId':421614,'contractAddress':address,'functionName':name,'args':args,'abi':function(abi,name)})['result']['result']
def write(step,address,name,args,abi):
    current=state['steps'].get(step)
    if not current:
        # API idempotency recovers a lost HTTP response; the key never changes.
        state['steps'][step]={'state':'submitting','key':'rescene/energy-drink-launch/'+step+'/v1'};save()
        headers={**HEAD,'Idempotency-Key':state['steps'][step]['key']}
        body={'chainId':421614,'walletAddress':TREASURY,'contractAddress':address,'functionName':name,'args':args,'abi':function(abi,name),'value':'0'}
        response=call('/v1/contracts/write',body,headers)['transaction']
        current=state['steps'][step]={**state['steps'][step],'id':response['id'],'state':response['status']};save()
    if 'id' not in current:raise RuntimeError('Submission uncertain; inspect Engine before retrying '+step)
    for _ in range(50):
        tx=call('/v1/transactions/'+current['id'])['transaction']
        current['state']=tx['status'];current['transactionHash']=tx.get('transactionHash','');save()
        if tx['status']=='confirmed':print(step,'confirmed',current['transactionHash'],flush=True);return tx
        if tx['status']=='failed':raise RuntimeError('Engine step failed; inspect transaction '+current['id'])
        time.sleep(2)
    raise RuntimeError('Still pending; rerun resumes the same Engine ID')
if __name__=='__main__':
    metadata={'name':'Energy Drink','description':'A refreshing boost for your next RESCENE Rhythm scene. Consume one to restore 5 energy, up to the 15-energy cap.','image':'https://engine.fluentxverse.com/items/energy-drink.png','attributes':[{'trait_type':'Type','value':'Consumable'},{'trait_type':'Energy','value':5}]}
    import base64
    uri='data:application/json;base64,'+base64.b64encode(json.dumps(metadata,separators=(',',':')).encode()).decode()
    state.update({'chainId':421614,'collection':COLLECTION,'marketplace':MARKET,'currency':TOKEN,'tokenId':'0','listingId':'0','unitPrice':'100','unitPriceRaw':'100000000000000000000','initialStock':10000,'metadata':metadata,'metadataURI':uri});save()
    if 'mint' not in state['steps']:
        assert read(COLLECTION,'nextTokenIdToMint',[],NFT)=='0','Collection already has items; inspect before launch'
    write('mint',COLLECTION,'mintTo',[TREASURY,str(2**256-1),uri,'10000'],NFT)
    assert read(COLLECTION,'nextTokenIdToMint',[],NFT)=='1','Unexpected extra token IDs; inspect Engine receipts'
    write('approve-marketplace',COLLECTION,'setApprovalForAll',[MARKET,'true'],NFT)
    if 'listing-valid-start' not in state['steps']:assert read(MARKET,'totalListings',[],LIST)=='0','Marketplace already has listings; inspect before launch'
    params={'assetContract':COLLECTION,'tokenId':'0','quantity':'10000','currency':TOKEN,'pricePerToken':'100000000000000000000','startTimestamp':str(int(time.time())),'endTimestamp':'2082758400','reserved':False}
    params=state.setdefault('listingParameters',params);save()
    write('listing-valid-start',MARKET,'createListing',[json.dumps(params,separators=(',',':'))],LIST)
    assert read(MARKET,'totalListings',[],LIST)=='1','Unexpected extra listings; inspect Engine receipts'
    state['verifiedListing']=read(MARKET,'getListing',['0'],LIST);state['status']='confirmed';save();print('Real Energy Drink token 0 listed for 100 STARL',flush=True)
