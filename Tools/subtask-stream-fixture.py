# coding: utf-8
"""Fixture под LOCK-SUBTASK-STREAM-REMOVE-20261010: карточка с идущим шагом и
живой активностью, чтобы снять кадр секции «Подзадачи» — ряд иконок выше
списка и отсутствие стрима под шагом. Ответ /api/tasks/:id/activity отдаёт и
общий текст, и действия по шагу — то, что раньше рисовалось как живой стрим."""
import json, hashlib, base64, struct
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

user = {"id": "u1", "name": "Максим", "role": "owner", "type": "human"}
STEP = "step1"

def actions():
    return [{"kind": k, "target": "Sources/%s/File%d.swift" % (k, i),
             "actor": "builder", "at": 1791532800000 + i * 1000,
             "text": "Действие %02d: %s в исходниках клиента" % (i, k)}
            for i, k in enumerate(["read", "edit", "run", "search", "test",
                                   "build", "git", "write", "web", "think"])]

def task():
    return {"id": "live", "title": "Проверка стрима под шагами", "status": "active",
            "creator_id": "u1", "agent_state": "in_progress",
            "labels": [], "comments": [], "events": [], "priority": 1, "children": [],
            "subtasks": [
                {"id": STEP, "task_id": "live", "position": 0, "done": False,
                 "state": "running", "agent_state": "in_progress",
                 "title": "Собрать и проверить правку карточки", "result": None},
                {"id": "step2", "task_id": "live", "position": 1, "done": True,
                 "title": "Согласовать формулировки", "result": "Правки согласованы."},
                {"id": "step3", "task_id": "live", "position": 2, "done": False,
                 "title": "Отдать владельцу на iPhone", "result": None}]}

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_POST(self): self.do_GET()
    def do_GET(self):
        path = self.path.split("?")[0]
        if path.endswith("/auth/me"): result = {"user": user}
        elif path.endswith("/auth/lan"): result = {"user": user, "token": "fixture"}
        elif path.endswith("/activity"):
            by = actions()
            result = {"text": "Разбирает правку секции подзадач в TaskFormScreen",
                      "actions": by, "total": len(by),
                      "by_subtask": {STEP: {"text": "Разбирает правку секции подзадач в TaskFormScreen",
                                             "actions": by, "total": len(by)}}}
        elif path == "/api/tasks/live": result = task()
        elif path == "/api/tasks": result = [task()]
        elif path.endswith("/live"): result = {"turns": []}
        elif path.endswith("/subtasks"): result = task()["subtasks"]
        elif path.endswith("/collaboration-plans"): result = {"plans": []}
        elif path.endswith("/preparation"): result = {"preparation": None}
        elif path == "/api/roles": result = {"roles": []}
        elif path == "/api/projects": result = []
        elif path == "/api/labels": result = []
        elif path.endswith("/reports"): result = []
        elif path.endswith("/chats"): result = {"chats": []}
        elif path.endswith("/avatars"): result = []
        elif path.endswith("/notes"): result = []
        else: result = {}
        data = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

ThreadingHTTPServer(("127.0.0.1", 3319), H).serve_forever()