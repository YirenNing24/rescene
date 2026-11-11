#!/usr/bin/env python3
"""Approve the confirmed PULSE event router for existing treasury stock."""
import fcntl,json,time
from pathlib import Path
import setup_energy_drink as e
ROOT=Path(__file__).resolve().parents[1]
RECORD=ROOT/'contracts/deployments/pulse-event-rewards-setup-2026.json'
launch=json.loads((ROOT/'contracts/deployments/pulse-event-rewards-2026.json').read_text())
assert launch['state']=='confirmed'
router=launch['receipt']['contractAddress'];abi=launch['request']['abi']
assert e.read(router,'treasury',[],abi).lower()==e.TREASURY.lower()
assert e.read(router,'token',[],abi).lower()==e.COLLECTION.lower()
assert e.read(router,'tokenId',[],abi)=='11'
assert int(e.read(e.COLLECTION,'balanceOf',[e.TREASURY,'11'],e.NFT))>=10
with RECORD.with_suffix('.lock').open('w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 state=json.loads(RECORD.read_text()) if RECORD.exists() else {'chainId':421614,'router':router,'steps':{}}
 assert state['router']==router
 def save():
  tmp=RECORD.with_suffix('.tmp');tmp.write_text(json.dumps(state,indent=2)+'\n');tmp.replace(RECORD)
 request={'chainId':421614,'contractAddress':e.COLLECTION,'walletAddress':e.TREASURY,'functionName':'setApprovalForAll','args':[router,'true'],'abi':e.function(e.NFT,'setApprovalForAll'),'value':'0'}
 step=state['steps'].setdefault('approve',{'request':request,'key':'rescene/event-refinement-2026/approve'});assert step['request']==request;save()
 if 'id' not in step:
  tx=e.call('/v1/contracts/write',request,{**e.HEAD,'Idempotency-Key':step['key']})['transaction'];step['id']=tx['id'];save()
 for _ in range(60):
  tx=e.call('/v1/transactions/'+step['id'])['transaction'];assert tx['contractAddress'].lower()==e.COLLECTION.lower() and tx['args']==request['args'] and tx['method']=='setApprovalForAll'
  step['status']=tx['status'];step['transactionHash']=tx.get('transactionHash','');save()
  if tx['status']=='confirmed':break
  if tx['status']=='failed':raise RuntimeError('Approval failed; inspect the saved transaction')
  time.sleep(2)
 else:raise RuntimeError('Approval pending; rerun resumes the same transaction')
 assert e.read(e.COLLECTION,'isApprovedForAll',[e.TREASURY,router],e.NFT) is True
 state['status']='confirmed';save();print('PULSE event item stock and approval verified on Arbitrum Sepolia.')
