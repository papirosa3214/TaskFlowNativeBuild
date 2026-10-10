import json,hashlib,base64,struct,threading
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
phase=0;clients=set()
user={"id":"u1","name":"Максим","role":"owner","type":"human"}
step={"id":"work-step","task_id":"work-task","title":"Подготовить результат","done":False,"position":0,"agent_id":"role_builder","agent_state":"in_progress","state":"running"}
def task():return {"id":"work-task","title":"Рабочие этапы исполнителя","description":"Проверка раскрытия рабочего списка","status":"active","creator_id":"u1","assignee_id":"role_builder","priority":1,"agent_state":"in_progress","subtasks":[step],"children":[],"comments":[],"events":[]}
def plan():return {"subtask_id":"work-step","revision":phase+1,"updated_at":"2026-10-10T16:00:00Z","author_id":"role_builder","items":[{"id":"read","title":"Изучить исходные данные","state":"done"},{"id":"make","title":"Подготовить результат","state":"done" if phase else "in_progress"},{"id":"verify","title":"Проверить результат","state":"in_progress" if phase else "pending"}]}
def frame(s,payload):
 b=json.dumps(payload,ensure_ascii=False).encode();s.sendall((bytes([129,len(b)]) if len(b)<126 else bytes([129,126])+struct.pack('!H',len(b)))+b)
class H(BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def log_message(self,*args):pass
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)));self.do_GET()
 def do_GET(self):
  global phase
  path=self.path.split('?')[0]
  if path=='/ws':
   self.send_response(101);self.send_header('Upgrade','websocket');self.send_header('Connection','Upgrade');self.send_header('Sec-WebSocket-Accept',base64.b64encode(hashlib.sha1((self.headers['Sec-WebSocket-Key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode());self.end_headers();s=self.connection;clients.add(s);frame(s,{'type':'connected'})
   try:
    while s.recv(4096):pass
   except Exception:pass
   clients.discard(s);return
  if path=='/probe/update':
   phase=1
   for s in list(clients):
    try:frame(s,{'type':'task:updated','task':task()})
    except Exception:clients.discard(s)
   result={}
  elif path=='/probe/reset':phase=0;result={}
  elif path.endswith('/auth/me'):result={'user':user}
  elif path.endswith('/auth/lan'):result={'user':user,'token':'fixture'}
  elif path=='/api/tasks':result=[task()]
  elif path=='/api/tasks/work-task':result=task()
  elif path.endswith('/work-plan'):result={'plan':plan()}
  elif path.endswith('/subtasks'):result=[step]
  elif path.endswith('/collaboration-plans'):result={'plans':[]}
  elif path.endswith('/preparation'):result={'preparation':None}
  elif path.endswith('/roles'):result={'roles':[]}
  elif path.endswith('/live'):result={'turns':[]}
  elif path.endswith('/activity'):result={'text':None,'actions':[],'by_subtask':{}}
  elif path.endswith('/chats'):result={'chats':[]}
  elif path in ['/api/projects','/api/labels','/api/notifications'] or path.endswith('/reports'):result=[]
  else:result={}
  data=json.dumps(result,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
ThreadingHTTPServer(('127.0.0.1',3320),H).serve_forever()
