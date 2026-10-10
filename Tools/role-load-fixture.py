import json
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs
user={"id":"u1","name":"Максим","role":"owner","type":"human"}
task={"id":"load-test","title":"Проверка загрузки ролей","description":"Проверяемый переход с полосы Ганта","status":"active","creator_id":"u1","priority":1,"subtasks":[],"children":[],"comments":[],"events":[]}
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)));self.do_GET()
 def do_GET(self):
  path=urlparse(self.path).path
  if path.endswith('/coordination/role-load'):
   window=parse_qs(urlparse(self.path).query).get('window',['24h'])[0]
   result={"window":window,"from":"2026-10-10T00:00:00Z","to":"2026-10-11T00:00:00Z","now":"2026-10-10T18:00:00Z","roles":[{"key":"builder","title":"Разработчик","position":1},{"key":"critic","title":"Критик","position":2},{"key":"qa","title":"Тестировщик","position":3}],"attempts":[{"id":"a1","task_id":"load-test","task_title":task['title'],"subtask_id":"s1","routing_role":"builder","started_at":"2026-10-10T02:00:00Z","ended_at":None,"outcome":None,"active":True}],"active_now":[{"id":"s1","task_id":"load-test","task_title":task['title'],"role_key":"builder","started_at":"2026-10-10T02:00:00Z","heartbeat_at":"2026-10-10T18:00:00Z"}],"open_slots":[{"id":"load-test","task_title":"Ожидает исполнителя","role_key":None,"state":"free"}]}
  elif path.endswith('/auth/me'): result={"user":user}
  elif path.endswith('/auth/lan'): result={"user":user,"token":"fixture"}
  elif path=='/api/tasks': result=[task]
  elif path=='/api/tasks/load-test': result=task
  elif path.endswith('/collaboration-plans'): result={"plans":[]}
  elif path.endswith('/preparation'): result={"preparation":None}
  elif path.endswith('/roles'): result={"roles":[]}
  elif path.endswith('/live'): result={"turns":[]}
  elif path.endswith('/chats'): result={"chats":[]}
  elif path in ['/api/projects','/api/labels','/api/notifications'] or path.endswith(('/subtasks','/reports')): result=[]
  else: result={}
  data=json.dumps(result,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
ThreadingHTTPServer(('127.0.0.1',3318),Handler).serve_forever()
