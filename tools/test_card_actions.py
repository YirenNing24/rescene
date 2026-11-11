#!/usr/bin/env python3
"""Exercise native card-action intents against an isolated API. No chain writes."""
import argparse, json, os, subprocess, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
state={'operation':None,'actions':{},'lost':False,'reads':0,'level':10,'xp':0,'stars':1,'donors':True,'locked':False,'deck':['','','','','']}
def progress():
    return {'level':1,'xp':0,'level_xp':0,'level_cost':200,'energy':{'current':15,'max':15,'next_recovery_at':None},'daily_reset_at':'2099-01-01T00:00:00','unlocks':[]}
def card(token,member):
    return {'id':f'pulse_{token}','template_id':f'scene_{member+1:02}','token_id':str(token),'set_id':'pulse','category':'cards','member_index':member,'member':['Woni','Liv','Minami'][member],'quantity':1,'level':state['level'] if token==14 else 90,'training_xp':state['xp'] if token==14 else 999,'stars':state['stars'] if token==14 else 5,'locked':state['locked'] if token==14 else False}
class API(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def send(self,data,code=200):
        raw=json.dumps(data).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
    def do_GET(self):
        if self.path=='/api/v1/shop/catalog':return self.send({'catalog':[{'id':'prism_shards','price':150,'training_xp':100,'stock':1000,'available':True,'max_quantity':10}]})
        if self.path=='/api/v1/progression':return self.send({'progression':progress()})
        if self.path=='/api/v1/starlight':return self.send({'starlight':{'status':'ready','balance':'1000'}})
        if self.path=='/api/v1/inventory':
            op=state['operation']
            if op and op['status']=='pending':
                state['reads']+=1
                if state['reads']>=2:
                    op['status']='confirmed';kind=op['body']['kind']
                    if kind=='refine':state['xp']+=100;op.update(level_upgraded=False,upgrade_attempted=True,level_after=10)
                    elif kind=='star':state['stars']=2;state['donors']=False
                    elif kind=='lock':state['locked']=op['body']['locked']
                    elif kind=='equip':state['deck'][op['body']['member_index']]=op['body']['card_id']
            items=[card(14,0),{'id':'prism_shards','quantity':2}]
            if state['donors']:items.extend([card(15,1),card(16,2)])
            return self.send({'items':items,'decks':{'pulse':state['deck']},'operation':op,'progression':progress()})
        if self.path=='/test/summary':return self.send({'count':len(state['actions']),'kinds':sorted(v['body']['kind'] for v in state['actions'].values())})
        return self.send({})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}')
        if self.path=='/api/v1/auth/login':return self.send({'user':{'id':'card-fixture','username':'Fixture'},'access_token':'fixture-access','refresh_token':'r'*43,'expires_in':3600,'refresh_expires_in':2592000,'refresh_expires_at':int(time.time())+2592000})
        if self.path=='/api/v1/collection/quote':
            assert 'quantity' not in body
            return self.send({'quote':{'hash':'fixture-'+body['kind'],'warnings':['Permanent card/item use.'],'level_before':10,'level_after':11,'success_chance_bp':9000,'stars_before':1,'stars_after':2}})
        if self.path=='/api/v1/collection/action':
            assert 'quantity' not in body,'Pulse actions must not acquire a legacy quantity field'
            assert body['acknowledge_warning'] is True
            if body['kind']=='equip':assert isinstance(body['member_index'],int),'Saved member index must be restored to an integer'
            key=body['request_id']
            if key not in state['actions']:
                op={'request_id':key,'kind':'pulse_'+body['kind'],'status':'pending','body':body};state['actions'][key]=op;state['operation']=op;state['reads']=0
            else:assert state['actions'][key]['body']==body,'A retry changed its immutable intent'
            if not state['lost']:state['lost']=True;return self.send({'error':{'message':'Lost fixture response'}},503)
            return self.send({'operation':state['actions'][key]})
        return self.send({})
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--godot',required=True);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='rescene-card-actions-') as temp:
        server=ThreadingHTTPServer(('127.0.0.1',0),API);threading.Thread(target=server.serve_forever,daemon=True).start()
        env=dict(os.environ,RESCENE_API_URL=f'http://127.0.0.1:{server.server_port}',RESCENE_AUTH_FILE=str(Path(temp)/'session.json'),RESCENE_CARD_ACTION_TEST='1')
        try:subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script','res://tests/pulse_actions_regression.gd'],env=env,check=True,timeout=60)
        finally:server.shutdown();server.server_close()
    assert len(state['actions'])==4 and state['level']==10 and state['xp']==100 and state['stars']==2 and not state['donors'] and state['locked'] and state['deck'][0]=='pulse_14'
    print('Native quoted card actions, failed refinement, exact donor use, five-slot deck and restart-safe intent: PASS')
if __name__=='__main__':main()
