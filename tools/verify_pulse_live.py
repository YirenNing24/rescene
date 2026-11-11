#!/usr/bin/env python3
"""Live Arbitrum Sepolia QA: one card purchase, one refine and deck equip.
No existing player is modified. Durable IDs recover uncertain responses.
"""
import json,time,secrets,urllib.error
from pathlib import Path
import setup_energy_drink as engine
import verify_launch_api as api
ROOT=Path(__file__).resolve().parents[1];PRIVATE=ROOT/'backend/data/vps-deployment';FILE=PRIVATE/'pulse-qa.json'
state=json.loads(FILE.read_text()) if FILE.exists() else {'steps':{},'requests':{}}
def save():FILE.write_text(json.dumps(state,indent=2));FILE.chmod(0o600)
def transaction(step,address,method,args,abi):
 body={'chainId':421614,'contractAddress':address,'walletAddress':engine.TREASURY,'functionName':method,'args':args,'abi':engine.function(abi,method),'value':'0'}
 op=state['steps'].setdefault(step,{'body':body,'key':'rescene/pulse-live-qa/'+api.state['user']['id']+'/'+step});assert op['body']==body;save()
 if 'id' not in op:op['id']=engine.call('/v1/contracts/write',body,{**engine.HEAD,'Idempotency-Key':op['key']})['transaction']['id'];save()
 for _ in range(90):
  tx=engine.call('/v1/transactions/'+op['id'])['transaction'];op.update(status=tx['status'],transactionHash=tx.get('transactionHash',''));save()
  if tx['status']=='confirmed':print(step,'confirmed',flush=True);return
  if tx['status']=='failed':raise RuntimeError('Inspect failed '+op['id'])
  time.sleep(2)
 raise RuntimeError('Transaction remains pending; rerun resumes exact ID')
def inventory():return api.call('/api/v1/inventory')
def action(step,path,body):
 op=state['requests'].setdefault(step,{'request_id':secrets.token_hex(16),**body});save();data=api.call(path,op)
 if (data.get('operation') or data.get('reward') or {}).get('status')=='confirmed':return inventory()
 for i in range(120):
  inv=inventory();job=inv.get('operation') or {}
  if job.get('request_id')==op['request_id'] and job.get('status')=='confirmed':state[step+'_receipt']=job;save();print(step,'confirmed',flush=True);return inv
  if job.get('status')=='failed':raise RuntimeError(job.get('error','Action failed'))
  if i%10==0:print(step,job.get('stage'),job.get('status'),flush=True)
  time.sleep(2)
 raise RuntimeError(step+' pending; durable ID preserved')
def quoted(step,body):
 if step not in state['requests']:
  quote=api.call('/api/v1/collection/quote',body)['quote'];body.update(quote_hash=quote['hash'],acknowledge_warning=True)
 return action(step,'/api/v1/collection/action',body)
def main():
 if 'wallet_address' not in api.state:
  for _ in range(40):
   wallet=api.call('/api/v1/wallet')['wallet']
   if wallet.get('status')=='ready':break
   time.sleep(2)
  assert wallet['status']=='ready';api.state['wallet_address']=wallet['address'];api.save()
 wallet=api.state['wallet_address']
 transfer=[{'type':'function','name':'transfer','stateMutability':'nonpayable','inputs':[{'name':'to','type':'address'},{'name':'amount','type':'uint256'}],'outputs':[{'name':'ok','type':'bool'}]}]
 transaction('qa-funding',engine.TOKEN,'transfer',[wallet,str(1000*10**18)],transfer)
 inv=action('card-purchase','/api/v1/shop/purchase',{'item_id':'scene_01','quantity':1,'expected_total':'450'})
 # The repeat must resolve to the same card/action, never another payment.
 api.call('/api/v1/shop/purchase',state['requests']['card-purchase']);inv=inventory()
 cards=[v for v in inv['items'] if str(v['id']).startswith('pulse_')];assert len(cards)==1
 card=cards[0];state['card_id']=card['id'];save();assert card['level']>=1 and card['stars']>=1 and 700<=card['base_score_bp']<=1000
 inv=action('material-purchase','/api/v1/shop/purchase',{'item_id':'prism_shards','quantity':1,'expected_total':'150'})
 inv=quoted('card-refine',{'kind':'refine','card_id':state['card_id'],'item_id':'prism_shards'})
 upgraded=next(v for v in inv['items'] if v['id']==state['card_id']);assert upgraded['level']==2
 inv=quoted('card-equip',{'kind':'equip','set_id':'pulse','member_index':0,'card_id':state['card_id']})
 assert inv['decks']['pulse'][0]==state['card_id']
 # Admin generation is explicitly outside the initial sale allocation. Create two
 # QA donor cards, then verify their irreversible burn and receiver-only star gain.
 pulse_abi=json.loads((ROOT/'contracts/out/PulseCards.sol/PulseCardsLaunch.json').read_text())['abi']
 for i in range(2):
  name='qa-donor-'+str(i)
  rolls=state.setdefault('admin_rolls',{}).setdefault(name,[str((7+secrets.randbelow(4))*100),str(7+secrets.randbelow(4)),str(1+secrets.randbelow(6))]);save()
  action_id='0x'+__import__('hashlib').sha256((api.state['user']['id']+'/'+name).encode()).hexdigest()
  transaction(name,'0xa9a2add390c43a521532824e75c88eeb437c10bc','generate',[action_id,wallet,str(i+1),'5',*rolls],pulse_abi)
 inv=inventory();donors=[v['id'] for v in inv['items'] if str(v['id']).startswith('pulse_') and v['id']!=state['card_id']]
 if 'card-star' not in state['requests']:assert len(donors)==2
 inv=quoted('card-star',{'kind':'star','card_id':state['card_id'],'donors':donors})
 remaining=[v for v in inv['items'] if str(v['id']).startswith('pulse_')];assert len(remaining)==1 and remaining[0]['stars']==2
 # A normal run spends one energy; abandon grants no score or rewards.
 if 'qa-run' not in state:
  chart=next(v for v in json.loads((ROOT/'backend/charts.json').read_text()) if v['difficulty']=='Easy' and v['title']=='BamBamBam')
  body={'request_id':secrets.token_hex(16),'song_id':chart['song_id'],'difficulty':chart['difficulty'],'revision':chart['revision'],'replay_version':3}
  state['qa-run']=api.call('/api/v1/runs',body)['reward']['id'];save()
 api.call('/api/v1/runs/'+state['qa-run']+'/abandon',{})
 inv=action('drink-purchase','/api/v1/shop/purchase',{'item_id':'energy_drink','quantity':1,'expected_total':'100'})
 inv=action('drink-consume','/api/v1/inventory/consume',{'item_id':'energy_drink','quantity':1})
 assert next(v for v in inv['items'] if v['id']=='energy_drink')['quantity']==0
 assert inv['progression']['energy']['current']==15
 try:api.call('/api/v1/inventory/consume',{'request_id':secrets.token_hex(16),'item_id':'energy_drink','quantity':1});raise AssertionError('Double use accepted')
 except urllib.error.HTTPError as error:assert error.code==409

 proof={'network':'Arbitrum Sepolia','router':'0xa9a2add390c43a521532824e75c88eeb437c10bc','qa_wallet':wallet,'card_id':state['card_id'],'checks':{'confirmed_payment_and_delivery':True,'purchase_retry_no_duplicate':True,'refinement_material_delivery':True,'refinement_burn_and_level':True,'album_member_equip':True,'star_upgrade_donors_burned':True,'energy_drink_consumed_once':True},'transactions':{k:v.get('transactionHash') for k,v in state['steps'].items()},'receipts':{k:state[k] for k in state if k.endswith('_receipt')}}
 (ROOT/'output/pulse-live-verification.json').write_text(json.dumps(proof,indent=2)+'\n');print('Live purchase → inventory → refine → PULSE equip: PASS',flush=True)
if __name__=='__main__':main()
