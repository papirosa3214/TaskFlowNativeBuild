"""Local fixture for the existing server-setting editor; never touches production."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
USER={'id':'u1','name':'Максим','role':'owner','type':'human'}
SETTING={'key':'chat_item_max_actions','label':'Действий на пункт чек-листа','group':'лимиты','kind':'int','default':10,'min':1,'max':1000,'description':'Один вызов инструмента — одно действие. Сдача пункта, управление планом и сообщение о ходе работы не расходуют лимит. После принятой сервером сдачи следующий пункт получает новый бюджет. Расход сохраняется при перезапуске хода. Изменение действует на следующие действия без рестарта сервера; уже выполненные не обнуляются.'}
value=10
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_PUT(self):
  global value
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or '{}');value=body['value'];self.respond({'ok':True})
 def do_POST(self):
  global value
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  if self.path.endswith('/reset'):value=10
  self.do_GET()
 def respond(self,result):
  data=json.dumps(result,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def do_GET(self):
  path=self.path.split('?')[0]
  if path.endswith('/auth/me'):result={'user':USER}
  elif path.endswith('/auth/lan'):result={'user':USER,'token':'local-fixture'}
  elif path=='/api/admin/server-settings':result={'settings':[SETTING],'values':{SETTING['key']:value},'updated_at':{}}
  elif path=='/api/admin/server-settings/log':result={'log':[]}
  elif path.endswith('/roles'):result={'roles':[]}
  elif path.endswith('/chats'):result={'chats':[]}
  elif path in ['/api/tasks','/api/projects','/api/labels','/api/notifications']:result=[]
  else:result={}
  self.respond(result)
ThreadingHTTPServer(('127.0.0.1',3340),Handler).serve_forever()
