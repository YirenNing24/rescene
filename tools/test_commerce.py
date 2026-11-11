#!/usr/bin/env python3
"""Native Godot checkout flow against a deterministic local API; no chain writes."""
import argparse, json, os, subprocess, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
state={'balance':100,'owned':0,'energy':9,'operation':None,'buys':{},'uses':{},'lost':False,'reads':0}
def progress():
    return {'energy':{'current':state['energy'],'max':15,'next_recovery_at':None},'starlight':100,'starlight_token':{'enabled':True},'level':1,'xp':0,'level_xp':0,'level_cost':200,'daily_reset_at':'2099-01-01T00:00:00','unlocks':[]}
class API(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def send(self,body,code=200):
        b=json.dumps(body).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def do_GET(self):
        p=self.path.split('?')[0]
        if p=='/api/v1/shop/catalog':return self.send({'catalog':[{'id':'energy_drink','price':100,'stock':10000,'available':True,'max_quantity':10}]})
        if p=='/api/v1/inventory':
            op=state['operation']
            if op and op['status']=='pending':
                state['reads']+=1
                if state['reads']>=2:
                    op['status']='confirmed'
                    if op['kind']=='buy':state['owned']+=1;state['balance']-=100
                    else:state['owned']-=1;state['energy']+=5
            return self.send({'enabled':True,'items':[{'id':'energy_drink','quantity':state['owned']}],'operation':op,'progression':progress()})
        if p=='/api/v1/progression':return self.send({'progression':progress()})
        if p=='/api/v1/starlight':return self.send({'starlight':{'status':'ready','balance':str(state['balance']),'pending':'0'}})
        if p=='/api/v1/marketplace':return self.send({'marketplace':{'status':'connected','total_listings':'1'}})
        if p=='/test/summary':return self.send({'buys':len(state['buys']),'uses':len(state['uses']),'energy':state['energy']})
        return self.send({'records':[]})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}')
        if self.path=='/api/v1/auth/login':return self.send({'user':{'id':'fixture-player','username':'Fixture'},'access_token':'fixture-access','refresh_token':'r'*43,'expires_in':3600,'refresh_expires_in':2592000,'refresh_expires_at':int(time.time())+2592000})
        if self.path in ['/api/v1/shop/purchase','/api/v1/inventory/consume']:
            assert isinstance(body['quantity'],int),'saved JSON quantity must be converted to integer'
            kind='buy' if self.path.endswith('purchase') else 'consume';ledger=state['buys'] if kind=='buy' else state['uses']
            if body['request_id'] not in ledger:
                ledger[body['request_id']]={'request_id':body['request_id'],'kind':kind,'status':'pending','quantity':1}
                state['operation']=ledger[body['request_id']];state['reads']=0
            if kind=='buy' and not state['lost']:
                state['lost']=True;return self.send({'error':{'message':'Lost test response'}},503)
            return self.send({'operation':ledger[body['request_id']]})
        return self.send({})
def main():
    p=argparse.ArgumentParser();p.add_argument('--godot',required=True);args=p.parse_args()
    with tempfile.TemporaryDirectory(prefix='rescene-commerce-') as temp:
        server=ThreadingHTTPServer(('127.0.0.1',0),API);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        environment=dict(os.environ,RESCENE_API_URL=f'http://127.0.0.1:{server.server_port}',RESCENE_AUTH_FILE=str(Path(temp)/'session.json'),RESCENE_COMMERCE_TEST='1')
        try:subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script','res://tests/commerce_flow_regression.gd'],env=environment,check=True,timeout=60)
        finally:server.shutdown();server.server_close()
        assert len(state['buys'])==1 and len(state['uses'])==1 and state['owned']==0 and state['balance']==0 and state['energy']==14
        print('Durable checkout intent, lost response, restored request, confirmed inventory and consumption: PASS')
if __name__=='__main__':main()
