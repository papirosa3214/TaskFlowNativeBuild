# coding: utf-8
import json, threading, hashlib, base64, struct, time, socket
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
clients=set(); counts={}; phase=0; activity_hits=0; live_hits=0
user={"id":"u1","name":"Максим","role":"owner","type":"human"}
def task():
 return {"id":"energy","title":"Проверка WebSocket","status":"active","creator_id":"u1","subtasks":[{"id":"step","task_id":"energy","title":["Шаг до события","Шаг после события","Шаг после переподключения"][min(phase,2)],"done":False,"position":0}],"children":[],"comments":[],"events":[],"priority":1}
def frame(s,payload):
 b=json.dumps(payload,ensure_ascii=False).encode(); head=bytes([129,len(b)]) if len(b)<126 else bytes([129,126])+struct.pack("!H",len(b)); s.sendall(head+b)
class H(BaseHTTPRequestHandler):
 protocol_version="HTTP/1.1"
 def log_message(self,*a): pass
 def do_POST(self): self.do_GET()
 def do_GET(self):
  global phase
  path=self.path.split("?")[0]
  if path=="/ws":
   self.send_response(101);self.send_header("Upgrade","websocket");self.send_header("Connection","Upgrade");self.send_header("Sec-WebSocket-Accept",base64.b64encode(hashlib.sha1((self.headers["Sec-WebSocket-Key"]+"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode());self.end_headers()
   s=self.connection;clients.add(s);frame(s,{"type":"connected"})
   try:
    while s.recv(4096): pass
   except Exception: pass
   clients.discard(s);return
  if path=="/probe/reset": counts.clear();phase=0; result={}
  elif path=="/probe/counts": result=counts.copy();result["__sockets"]=len(clients)
  elif path=="/probe/change":
   phase=min(2,phase+1)
   if "silent=1" not in self.path:
    for s in list(clients):
     try: frame(s,{"type":"task:changed","task_id":"energy"})
     except Exception: clients.discard(s)
   result={}
  elif path=="/probe/disconnect":
   for s in list(clients):
    try:s.shutdown(socket.SHUT_RDWR);s.close()
    except Exception:pass
   clients.clear();result={}
  else:
   counts[path]=counts.get(path,0)+1
   if path.endswith("/auth/me"):result={"user":user}
   elif path.endswith("/auth/lan"):result={"user":user,"token":"fixture"}
   elif path=="/api/tasks":result=[task()]
   elif path=="/api/tasks/energy":result=task()
   elif path.endswith("/subtasks"):result=task()["subtasks"]
   elif path.endswith("/collaboration-plans"):result={"plans":[{"id":"p1","task_id":"energy","revision":1,"status":"approved","profile":"product_feature","rationale":"Fixture","nodes":[{"slot_key":"builder","role_key":"builder","required":True,"expected_result":"Проверка окна","task_id":"energy","source_subtask_id":"step","execution_state":"active"}],"edges":[]}]}
   elif path.endswith("/preparation"):result={"preparation":None}
   elif path.endswith("/activity"):
    global activity_hits
    activity_hits+=1
    result={"text":None,"actions":[],"by_subtask":{"step":{"text":"Проверка накопленной истории, обновлений %d"%activity_hits,"actions":[{"kind":"read","target":str(i),"actor":"builder","at":1791532800000+i*1000,"text":"Событие %02d: проверяется накопленная история роли в ограниченном окне"%i} for i in range(40)],"total":40}}}
   elif path.endswith("/live"):result={"turns":[live_turn()]}
   elif path=="/api/roles":result={"roles":[]}
   elif path=="/api/notifications":result=[]
   elif path.endswith("/chats"):result={"chats":[]}
   elif path.endswith("/reports"):result=[]
   elif path in ["/api/projects","/api/labels"]:result=[]
   elif path.endswith("/avatars"):result=[]
   else:result={}
  data=json.dumps(result,ensure_ascii=False).encode()
  self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(data)));self.end_headers();self.wfile.write(data)
def live_turn():
 # Живой ход растёт по словам — как в бою, пока модель пишет ответ.
 global live_hits
 live_hits+=1
 text="\n\n".join("Событие %02d: проверяется накопленная история роли в ограниченном окне"%i for i in range(live_hits))
 return {"task_id":"energy","subtask_id":"step","run_id":"run-1","complete":False,
         "turn":{"chat_id":"energy","user_id":"u1","name":"Разработчик",
                 "started_at":"2026-10-25T02:00:00Z",
                 "items":[{"kind":"text","text":text}],"thinking":None}}

def pump():
 # События активности и живого хода раз в секунду: как в бою, когда идёт ход.
 while True:
  time.sleep(1)
  for sock in list(clients):
   try:
    frame(sock,{"type":"task:activity","task_id":"energy"})
    turn=live_turn()
    turn["type"]="tasks:live"
    frame(sock,turn)
   except Exception: clients.discard(sock)
threading.Thread(target=pump,daemon=True).start()
print("WebSocket fixture listening on 3307",flush=True)
ThreadingHTTPServer(("127.0.0.1",3307),H).serve_forever()
