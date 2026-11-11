#!/usr/bin/env python3
"""Durable, non-secret public smoke report. Uses a dedicated QA account only."""
import json,secrets,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];PRIVATE=ROOT/'backend/data/vps-deployment';STATE=PRIVATE/'qa-player.json';BASE='https://api.remineph.online'
if STATE.exists():state=json.loads(STATE.read_text())
else:state={'username':'launch_'+secrets.token_hex(4),'password':secrets.token_urlsafe(24)}
def save():STATE.write_text(json.dumps(state));STATE.chmod(0o600)
def call(path,data=None,authorized=True):
 headers={'Content-Type':'application/json','User-Agent':'REMINE-Launch-Check/1.0'}
 if authorized:headers['Authorization']='Bearer '+state['access_token']
 if path=='/api/v1/auth/register' and data is not None:
  policy=json.loads((ROOT/'assets/legal/policies.json').read_text())
  data={**data,'accept_policies':True,'terms_version':policy['version'],'privacy_version':policy['version']}
 req=urllib.request.Request(BASE+path,data=None if data is None else json.dumps(data).encode(),headers=headers)
 for attempt in range(4):
  try:
   with urllib.request.urlopen(req,timeout=40) as r:return json.load(r)
  except urllib.error.HTTPError as error:
   if error.code not in [502,503,504] or attempt==3:raise
  except (urllib.error.URLError,ConnectionError,TimeoutError):
   if attempt==3:raise
  time.sleep(2)
def main():
 save();print('Health',call('/healthz',authorized=False),flush=True)
 if 'access_token' not in state:
  body={'username':state['username'],'password':state['password']}
  try:session=call('/api/v1/auth/register',body,False)
  except urllib.error.HTTPError as e:
   if e.code!=409:raise
   session=call('/api/v1/auth/login',body,False)
  state.update(session);save()
 me=call('/api/v1/auth/me');assert me['user']['id']==state['user']['id']
 report={'api':BASE,'account_id':me['user']['id'],'checks':{}}
 for name,path in [('progression','/api/v1/progression'),('social','/api/v1/social'),('challenges','/api/v1/challenges'),('account_security','/api/v1/account/security'),('shop','/api/v1/shop/catalog')]:
  start=time.monotonic();data=call(path);report['checks'][name]={'status':'pass','seconds':round(time.monotonic()-start,2)}
  if name=='shop':
   cards=[v for v in data['catalog'] if v.get('generation')=='individual_randomized'];assert len(cards)==5 and all(v['initial_allocation']==50 for v in cards)
   report['checks'][name]['products']=[{'id':v['id'],'available':v['available'],'stock':v.get('stock')} for v in data['catalog']]
  print(name,'PASS',flush=True)
 for _ in range(40):
  wallet=call('/api/v1/wallet')['wallet']
  if wallet.get('status')=='ready':break
  time.sleep(2)
 assert wallet['status']=='ready';report['wallet']=wallet['address'];state['wallet_address']=wallet['address'];save()
 inv=call('/api/v1/inventory');assert inv['enabled'];report['checks']['inventory']={'status':'pass'}
 (ROOT/'output/vps-public-api-verification.json').write_text(json.dumps(report,indent=2)+'\n');print('Public API, wallet, inventory and launch catalog: PASS')
if __name__=='__main__':main()
