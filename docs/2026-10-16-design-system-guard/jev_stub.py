"""Временный заглушечный сервер для UI-проверки экрана «Оценщик JEV».

Даёт приложению минимум, чтобы экран настроек JEV отрисовался с тумблерами:
владельца (/api/auth/me) и настройки JEV (/api/jev/settings). Живёт только
на время съёмки кадра, в репозиторий не входит.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER = {
    "id": "debug-owner",
    "name": "Максим",
    "email": "debug@local",
    "role": "owner",
    "type": "human",
    "status": "online",
    "initials": "М",
}

JEV = {
    "baseUrl": "http://127.0.0.1:11434",
    "model": "qwen2.5",
    "timeoutMs": 30000,
    "hasApiKey": True,
    "planProfileEnabled": True,
    "subtaskRoleEnabled": True,
    "memoryRecallEnabled": True,
    "memoryWriteEnabled": False,
    "skillsEnabled": True,
}


class Handler(BaseHTTPRequestHandler):
    def _send(self, payload, code=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.endswith("/auth/me"):
            return self._send({"user": USER})
        if self.path.endswith("/jev/settings"):
            return self._send(JEV)
        return self._send([])

    def do_PUT(self):
        return self._send(JEV)

    def do_POST(self):
        return self._send({"ok": True, "models": ["qwen2.5"], "ms": 12})

    def do_DELETE(self):
        return self._send(JEV)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 3399), Handler).serve_forever()
