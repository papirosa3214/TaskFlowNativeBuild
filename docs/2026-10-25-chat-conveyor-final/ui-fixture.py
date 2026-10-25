"""Read-only local fixture for a screenshot of the normal chat. No live models or production data."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
USER = {'id':'u1','name':'Максим','role':'owner','type':'human'}
ROLE = {'id':'role_builder','name':'Разработчик','role_key':'builder'}
CHAT = {'id':'conveyor-preview','title':'Разработчик','kind':'direct','created_by':'u1','execution_mode':'chat','members':[USER,ROLE]}
PLAN = {'chat_id':CHAT['id'],'role_id':ROLE['id'],'revision':2,'status':'active','current_item_id':'verify','updated_at':'2026-10-25T10:00:00Z','items':[
 {'id':'inspect','title':'Изучить исходные данные','state':'done','result':'Данные сверены.'},
 {'id':'verify','title':'Проверить результат','state':'in_progress'},
 {'id':'report','title':'Подготовить итог','state':'pending'}]}
MESSAGES = [
 {'id':'owner-message','chat_id':CHAT['id'],'from_user_id':'u1','from_name':'Максим','text':'Сверь данные, проверь результат и подготовь итог.','queue_delivery_state':'accepted','created_at':'2026-10-25T10:00:00Z','is_session_marker':False},
 {'id':'role-message','chat_id':CHAT['id'],'from_user_id':ROLE['id'],'from_name':ROLE['name'],'text':'Исходные данные сверены. Проверяю результат — это второй пункт плана.','created_at':'2026-10-25T10:01:00Z','is_session_marker':False}]
class Handler(BaseHTTPRequestHandler):
 def log_message(self, *args): pass
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)))
  self.do_GET()
 def do_GET(self):
  path=self.path.split('?')[0]
  if path.endswith('/auth/me'): result={'user':USER}
  elif path.endswith('/auth/lan'): result={'user':USER,'token':'local-fixture'}
  elif path.endswith('/work-plans'): result={'plans':[PLAN]}
  elif path.endswith('/messages'): result={'messages':MESSAGES}
  elif path.endswith('/live'): result={'turns':[]}
  elif path.endswith('/topics'): result={'chats':[]}
  elif path.endswith('/chats/rooms'): result={'personal':[],'direct':[],'groups':[]}
  elif path.endswith('/chats'): result={'chats':[CHAT]}
  elif path.endswith('/chats/'+CHAT['id']): result={'chat':CHAT}
  elif path.endswith('/roles'): result={'roles':[]}
  elif path in ['/api/tasks','/api/projects','/api/labels','/api/notifications','/api/users']: result=[]
  else: result={}
  data=json.dumps(result,ensure_ascii=False).encode()
  self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
ThreadingHTTPServer(('127.0.0.1',3339), Handler).serve_forever()
