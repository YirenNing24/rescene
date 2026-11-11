#!/usr/bin/env python3
"""Idempotent PULSE testnet setup; durable requests never mint twice on retries."""
import argparse,base64,fcntl,json,subprocess,time
from pathlib import Path
import setup_energy_drink as e
ROOT=Path(__file__).resolve().parents[1];RECORD=ROOT/'contracts/deployments/pulse-setup-v3.json'
launch=json.loads((ROOT/'contracts/deployments/pulse-cards-launch-v3.json').read_text());PULSE=launch['receipt']['contractAddress'];ABI=json.loads((ROOT/'contracts/out/PulseCards.sol/PulseCardsLaunch.json').read_text())['abi']
def main():
 p=argparse.ArgumentParser();p.add_argument('--execute',action='store_true');p.add_argument('--open-sales',action='store_true');args=p.parse_args()
 if not args.execute:print('Use --execute to configure existing PULSE testnet deployment. --open-sales opens its initial 50/member allocation.');return
 lock=RECORD.with_suffix('.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 state=json.loads(RECORD.read_text()) if RECORD.exists() else {'chainId':421614,'router':PULSE,'initialAllocationPerMember':50,'artworkMayBeReissued':True,'adminMintingOutsideAllocation':True,'steps':{}}
 assert state['router']==PULSE
 def save():
  tmp=RECORD.with_suffix('.tmp');tmp.write_text(json.dumps(state,indent=2)+'\n');tmp.replace(RECORD)
 def write(step,address,method,values,abi):
  request={'chainId':421614,'contractAddress':address,'walletAddress':e.TREASURY,'functionName':method,'args':values,'abi':e.function(abi,method),'value':'0'}
  current=state['steps'].setdefault(step,{'request':request,'key':'rescene/pulse-setup-v3/'+step});assert current['request']==request;save()
  if 'id' not in current:
   current['id']=e.call('/v1/contracts/write',request,{**e.HEAD,'Idempotency-Key':current['key']})['transaction']['id'];save()
  for _ in range(90):
   tx=e.call('/v1/transactions/'+current['id'])['transaction'];assert tx['contractAddress'].lower()==address.lower() and tx['method']==method and tx['args']==values
   current['status']=tx['status'];current['transactionHash']=tx.get('transactionHash','');save()
   if tx['status']=='confirmed':print(step,'confirmed',flush=True);return
   if tx['status']=='failed':raise RuntimeError('Inspect failed transaction '+current['id'])
   time.sleep(2)
  raise RuntimeError('Pending; rerun resumes the same transaction')
 def uri(data):return 'data:application/json;base64,'+base64.b64encode(json.dumps(data,separators=(',',':')).encode()).decode()
 # IDs 6–10 were reserved by the previous, never-deployed draft. Retire them
 # explicitly to keep all material IDs stable; they are never player cards.
 for token in range(6,11):
  step='retire-slot-'+str(token)
  if step not in state['steps']:assert e.read(e.COLLECTION,'nextTokenIdToMint',[],e.NFT)==str(token)
  write(step,e.COLLECTION,'mintTo',[e.TREASURY,str(2**256-1),uri({'name':'Retired draft slot','description':'Non-playable reserved ID; burned during PULSE launch.'}),'1'],e.NFT)
  write('burn-slot-'+str(token),e.COLLECTION,'burn',[e.TREASURY,str(token),'1'],e.NFT)
 for token,name,xp in [(11,'Refine Dust',100),(12,'Refine Crystal',225),(13,'Refine Prism',450)]:
  step='material-'+str(token)
  if step not in state['steps']:assert e.read(e.COLLECTION,'nextTokenIdToMint',[],e.NFT)==str(token)
  data={'name':name,'description':f'Adds {xp} refinement XP to a member card. Level attempts may fail; XP is retained on failure.','attributes':[{'trait_type':'Refinement XP','value':xp}]}
  write(step,e.COLLECTION,'mintTo',[e.TREASURY,str(2**256-1),uri(data),'10000'],e.NFT)
 for role in ['MINTER_ROLE','METADATA_ROLE']:
  digest=subprocess.check_output(['cast','keccak',role],text=True).strip()
  write('grant-'+role,e.COLLECTION,'grantRole',[digest,PULSE],e.NFT)
 write('approve-material-stock',e.COLLECTION,'setApprovalForAll',[PULSE,'true'],e.NFT)
 for listing in range(1,6):write('retire-first-scene-listing-'+str(listing),e.MARKET,'cancelListing',[str(listing)],e.LIST)
 assert e.read(PULSE,'INITIAL_LE_ALLOCATION',[],ABI)=='50'
 assert e.read(PULSE,'ARTWORK_MAY_BE_REISSUED',[],ABI) is True
 for token in range(11,14):assert int(e.read(PULSE,'materialStock',[str(token)],ABI))>0
 state['configured']=True;save()
 if args.open_sales:
  write('open-initial-sale',PULSE,'setSalesEnabled',['true'],ABI)
  assert e.read(PULSE,'salesEnabled',[],ABI) is True
  state['salesEnabled']=True;save()
 print('PULSE configured:',PULSE,flush=True)
if __name__=='__main__':main()
