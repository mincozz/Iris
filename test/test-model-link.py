#!/usr/bin/env python3
"""Test de model-link : agent « openai » (aucun compte, aucun réseau externe).

    test/test-model-link.py

Règles pures (config, URL, fichier de clé) puis, avec un faux serveur HTTP
local, le streaming, l'arrêt, les erreurs et la mémoire envoyée.
"""
import json
import os
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = tempfile.mkdtemp(prefix="iris-ml-")
os.environ.update(HOME=HOME, IRIS_LANG="en")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import assistant as A  # noqa: E402

fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


# ── T1 : configuration et règles pures ───────────────────────────────────
OK = {"type": "openai", "base_url": "http://localhost:11434/v1", "models": {"fast": "a", "power": "b"}}
check(A.valid_agent(OK), "entrée openai valide")
check(A.valid_agent({"command": ["echo", "{prompt}"]}), "entrée command inchangée")
check(A.valid_agent({**OK, "base_url": "https://api.deepseek.com/v1", "key_file": "~/k", "timeout": 30,
                     "history": 4, "send_memory": True}), "options openai valides")
for label, bad in [
    ("sans base_url", {k: v for k, v in OK.items() if k != "base_url"}),
    ("schéma ftp", {**OK, "base_url": "ftp://localhost/v1"}),
    ("http hors local", {**OK, "base_url": "http://example.com/v1"}),
    ("http sur une IP du LAN", {**OK, "base_url": "http://192.168.1.5:11434/v1"}),
    ("modèle non texte", {**OK, "models": {"fast": 3}}),
    ("timeout nul", {**OK, "timeout": 0}),
    ("timeout booléen", {**OK, "timeout": True}),
    ("send_memory non booléen", {**OK, "send_memory": "oui"}),
    ("key_file non texte", {**OK, "key_file": 3}),
    ("type inconnu", {**OK, "type": "anthropic"}),
]:
    check(not A.valid_agent(bad), "refusé : " + label)

for url, ok, local in [
    ("http://localhost:11434/v1", True, True), ("http://127.0.0.1:1234/v1", True, True),
    ("http://[::1]:8080/v1", True, True), ("http://mon-pc.local/v1", True, True),
    ("https://api.deepseek.com/v1", True, False), ("https://localhost/v1", True, True),
    ("http://example.com/v1", False, False), ("http://localhost.evil.com/v1", False, False),
    ("http://127.0.0.1.evil.com/v1", False, False), ("ftp://localhost/v1", False, True),
    ("localhost:11434", False, False), ("", False, False),
]:
    check(A.endpoint_ok(url) is ok, f"endpoint_ok({url!r}) = {ok}")
    check(A.is_local(url) is local, f"is_local({url!r}) = {local}")


def keyfile(content, mode):
    p = tempfile.mktemp(dir=HOME)
    with open(p, "w") as f:
        f.write(content)
    os.chmod(p, mode)
    return p


check(A.read_key(keyfile("sk-123\n", 0o600)) == "sk-123", "clé 0600 lue et nettoyée")
for label, path in [("0644", keyfile("sk", 0o644)), ("0660", keyfile("sk", 0o660)),
                    ("vide", keyfile("\n", 0o600)), ("absente", os.path.join(HOME, "nope"))]:
    try:
        A.read_key(path)
        check(False, "clé refusée : " + label)
    except ValueError as e:
        check("sk" not in str(e) or label == "absente", "clé refusée : " + label)

# ── T2 : streaming, arrêt, redirection (faux serveur local) ──────────────
def sse(*deltas, done=True):
    out = b"".join(b"data: " + json.dumps(d).encode() + b"\n\n" for d in deltas)
    return out + (b"data: [DONE]\n\n" if done else b"")


def delta(text=None, **extra):
    d = {"choices": [{"delta": ({"content": text} if text is not None else {}) | extra}]}
    return d


class Fake(BaseHTTPRequestHandler):
    mode = "chunks"
    log = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        Fake.log.append({"path": self.path, "auth": self.headers.get("Authorization"),
                         "body": json.loads(body)})
        m = Fake.mode
        if m == "redirect":
            self.send_response(302)
            self.send_header("Location", "http://evil.invalid/steal")
            self.end_headers()
            return
        if m in ("401", "404", "429", "500"):
            self.send_response(int(m))
            self.end_headers()
            self.wfile.write(b'{"error":{"message":"secret-detail sk-test-key"}}')
            return
        if m == "garbage":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"<html>not sse</html>\n")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        data = sse(delta("Hel"), delta(reasoning_content="think"), delta("lo "), delta(),
                   {"choices": [], "usage": {"total_tokens": 9}}, delta("wor\u00e9ld"),
                   done=m != "no-done")
        if m == "bytes":
            for b in data:
                self.wfile.write(bytes([b]))
                self.wfile.flush()
        elif m == "silent":
            self.wfile.write(sse(delta("Hi"), done=False))
            self.wfile.flush()
            time.sleep(8)
        elif m == "hang":
            time.sleep(8)
        else:
            self.wfile.write(data)


srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_address[1]}/v1"


class FakeDaemon:
    def __init__(self):
        self.events = []
        self.done = threading.Event()

    def on_event(self, agent, d):
        self.events.append(d)
        if d.get("type") == "result":
            self.done.set()

    def text(self):
        return "".join(e["event"]["delta"]["text"] for e in self.events if e["type"] == "stream_event")

    def result(self):
        return next((e for e in self.events if e["type"] == "result"), None)


def ask(mode, msg="Salut", spec=None, history=(), wait=10, stop_after=None, model=None):
    Fake.mode = mode
    Fake.log.clear()
    spec = {"type": "openai", "base_url": BASE, "models": {"fast": "m-fast", "power": "m-power"},
            "timeout": 5, **(spec or {})}
    A.CONFIG["agents"]["x"] = spec
    A.AGENT = "x"
    conv = A.Conversation({"messages": [*history, {"role": "user", "text": msg}]})
    d = FakeDaemon()
    agent = A.new_agent(d, conv, model or A.MODELS["fast"])
    t0 = time.time()
    agent.user(msg)
    if stop_after:
        time.sleep(stop_after)
        agent.interrupt()
    d.done.wait(wait)
    return d, agent, time.time() - t0


d, agent, _ = ask("chunks", history=[{"role": "user", "text": "avant"}, {"role": "assistant", "text": "ok"}])
req = Fake.log[0]
check(type(agent).__name__ == "OpenAIAgent", "new_agent aiguille vers OpenAIAgent")
check(d.text() == "Hello woré" "ld", "fragments assemblés, reasoning_content et usage ignorés")
check(d.result() and not d.result()["is_error"], "résultat final sans erreur")
check(len([e for e in d.events if e["type"] == "stream_event"]) == 3, "un text_delta par fragment")
check(req["path"] == "/v1/chat/completions" and req["body"]["stream"] is True, "POST /chat/completions en stream")
check(req["body"]["model"] == "m-fast", "modèle fast")
msgs = req["body"]["messages"]
check([m["role"] for m in msgs] == ["system", "user", "assistant", "user"] and msgs[-1]["content"] == "Salut",
      "système + historique + message")
check(req["auth"] is None, "pas de clé déclarée : pas d'en-tête Authorization")

d, *_ = ask("chunks", model=A.MODELS["power"])
check(Fake.log[0]["body"]["model"] == "m-power", "modèle power")

key = keyfile("sk-test-key\n", 0o600)
d, *_ = ask("chunks", spec={"key_file": key})
check(Fake.log[0]["auth"] == "Bearer sk-test-key", "clé envoyée en Bearer")

d, *_ = ask("bytes")
check(d.text() == "Hello woré" "ld", "flux découpé octet par octet (UTF-8 coupé)")
d, *_ = ask("no-done")
check(d.text().endswith("ld") and not d.result()["is_error"], "fin de flux sans [DONE]")

d, _, dt = ask("silent", stop_after=1)
check(d.text() == "Hi" and d.result() and not d.result()["is_error"] and dt < 3,
      f"stop coupe un serveur muet ({dt:.1f}s)")

d, *_ = ask("redirect")
check(d.result() and d.result()["is_error"] and "evil" not in str(d.result()), "redirection refusée")

# ── T3 : erreurs lisibles, délai, pas de fuite de la clé ──────────────────
def error_of(d):
    r = d.result()
    return r["result"] if r and r["is_error"] else None


for mode, want in [("401", "key"), ("404", "model"), ("429", "limit"), ("500", "server error"),
                   ("garbage", "usable")]:
    d, *_ = ask(mode, spec={"key_file": key})
    e = error_of(d)
    check(e is not None and want in e.lower(), f"erreur {mode} lisible : {e}")
    check("sk-test-key" not in str(d.events) and "secret-detail" not in str(d.events),
          f"erreur {mode} : ni clé ni corps du serveur")

d, _, dt = ask("hang", spec={"timeout": 1})
check(error_of(d) and "1" in error_of(d) and dt < 4, f"délai dépassé signalé ({dt:.1f}s) : {error_of(d)}")

d, _, dt = ask("hang", stop_after=1)
check(d.result() and not d.result()["is_error"] and dt < 3, f"stop avant la moindre réponse ({dt:.1f}s)")

d, *_ = ask("chunks", spec={"base_url": "http://127.0.0.1:1/v1"})
check(error_of(d) and "127.0.0.1" in error_of(d), f"connexion refusée : {error_of(d)}")

d, *_ = ask("chunks", spec={"key_file": os.path.join(HOME, "absente")})
check(error_of(d) and "absente" in error_of(d), f"clé illisible : {error_of(d)}")

# ── T4 : mémoire jamais envoyée à un hôte distant par défaut ─────────────
os.makedirs(os.path.dirname(A.MEMORY_FILE), exist_ok=True)
with open(A.MEMORY_FILE, "w") as f:
    f.write("SECRET-MEMORY-LINE")


def system_of(mode="chunks", **spec):
    ask(mode, spec=spec)
    return Fake.log[0]["body"]["messages"][0]["content"]


check("SECRET-MEMORY-LINE" in system_of(), "hôte local : mémoire envoyée par défaut")
check("SECRET-MEMORY-LINE" not in system_of(send_memory=False), "hôte local, send_memory faux : pas de mémoire")
remote = {"type": "openai", "base_url": "https://api.example.com/v1"}
for flag, want in [({}, False), ({"send_memory": True}, True), ({"send_memory": False}, False)]:
    A.CONFIG["agents"]["r"] = {**remote, **flag}
    A.AGENT = "r"
    a = A.new_agent(FakeDaemon(), A.Conversation({"messages": [{"role": "user", "text": "x"}]}), "m")
    check(("SECRET-MEMORY-LINE" in a._system()) is want, f"hôte distant {flag or 'par défaut'} : mémoire {want}")

A.CONFIG["agents"]["cli"] = {"command": ["echo"]}
for name, want in [("claude", False), ("x", False), ("r", True), ("cli", False)]:
    A.AGENT = name
    check(A.agent_remote() is want, f"agent_remote({name}) = {want}")

if fails:
    print(f"\n{len(fails)} échec(s)")
    sys.exit(1)
print("\ntout est bon")
