#!/usr/bin/env python3
"""Opt-in testnet smoke using the dedicated verified-play event QA account."""
import json,time,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[1]
qa=json.loads((root/'backend/data/vps-deployment/event-qa-private.json').read_text())
base='https://api.remineph.online';token=''
def call(method,path,body=None):
 data=None if body is None else json.dumps(body).encode()
 headers={'Content-Type':'application/json','User-Agent':'Mozilla/5.0'}
 if token:headers['Authorization']='Bearer '+token
 req=urllib.request.Request(base+path,data=data,headers=headers,method=method)
 with urllib.request.urlopen(req,timeout=30) as response:return json.load(response)
login=call('POST','/api/v1/auth/login',qa);token=login['access_token']
song='ca722c0b0e8b'
state=call('GET','/api/v1/mastery/'+song)['mastery']
mission=next(m for m in state['milestones'] if m['id']=='full_combo')
if not mission['complete']:raise RuntimeError('QA account has no verified full-combo milestone')
if mission['claimed']:
 print('QA mastery reward was already claimed; live mastery read verified.')
else:
 def quantity():
  inventory=call('GET','/api/v1/inventory')
  return next((v['quantity'] for v in inventory['items'] if v['id']=='prism_shards'),0)
 before=quantity();path='/api/v1/mastery/'+song+'/full_combo/claim'
 reward=call('POST',path,{})['reward'];assert reward['shards']==1
 assert call('POST',path,{})['reward']['already_claimed'] is True
 for _ in range(36):
  q=quantity()
  if q==before+1:print('Live verified mastery claim and exactly one refinement bundle delivered.');break
  if q>before+1:raise RuntimeError('Unexpected duplicate bundle delivery')
  time.sleep(5)
 else:raise RuntimeError('Item delivery remains pending')
