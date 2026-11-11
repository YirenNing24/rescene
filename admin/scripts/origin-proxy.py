#!/usr/bin/env python3
"""Restrict the tunnel to signed admin endpoints; never expose player routes."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
class Gateway(BaseHTTPRequestHandler):
 def do_GET(self): self.proxy()
 def do_POST(self): self.proxy()
 def log_message(self, *_): pass
 def proxy(self):
  if not self.path.startswith('/api/admin/v1/'):
   self.send_error(404);return
  try:
   size=int(self.headers.get('Content-Length','0'))
   if size<0 or size>8388608: self.send_error(413);return
   self.connection.settimeout(25)
   raw=self.rfile.read(size)
   conn=http.client.HTTPConnection('127.0.0.1',8080,timeout=24)
   headers={k:v for k,v in self.headers.items() if k.lower() not in ('host','connection','transfer-encoding','accept-encoding')}
   conn.request(self.command,self.path,body=raw,headers=headers)
   res=conn.getresponse();data=res.read(16777217)
   if len(data)>16777216: self.send_error(502);return
   self.send_response(res.status)
   for k,v in res.getheaders():
    if k.lower() not in ('connection','transfer-encoding','content-length','server','date'):self.send_header(k,v)
   self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data);conn.close()
  except (OSError,ValueError,http.client.HTTPException): self.send_error(502)
ThreadingHTTPServer(('127.0.0.1',8083),Gateway).serve_forever()
