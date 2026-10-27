#!/usr/bin/env python3
"""Changement d'agent depuis le panneau, côté daemon (aucun compte, aucun quota).

HOME jetable, faux agents en `sh` : liste annoncée, changement mémorisé dans le
fichier `agent`, message envoyé au nouvel agent, nom inconnu ignoré, refus
pendant une réponse, restauration au redémarrage et repli sur claude.
"""
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


home = tempfile.mkdtemp(prefix="iris-switch-")
data = os.path.join(home, ".local/share/qs-assistant")
os.makedirs(data)
state = os.path.join(data, "agent")


def write_config(agents):
    with open(os.path.join(data, "config.json"), "w") as f:
        json.dump({"language": "en", "agents": agents}, f)


ECHO = {"command": ["cat"], "models": {"fast": "x", "power": "x"}}
SLOW = {"command": ["sh", "-c", "sleep 2; echo slow-done"], "models": {"fast": "x", "power": "x"}}


class Daemon:
    def __init__(self):
        self.p = subprocess.Popen([sys.executable, os.path.join(ROOT, "scripts/assistant.py")],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1,
                                  env=dict(os.environ, HOME=home))
        self.lines = queue.Queue()
        threading.Thread(target=lambda: [self.lines.put(ln) for ln in self.p.stdout] and self.lines.put(None),
                         daemon=True).start()

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def until(self, pred, timeout=20):
        end = time.time() + timeout
        while time.time() < end:
            try:
                line = self.lines.get(timeout=0.5)
            except queue.Empty:
                continue
            if line is None:
                break
            d = json.loads(line)
            if pred(d):
                return d
        return None

    def agents(self):
        d = self.until(lambda d: d["t"] == "agents")
        return d

    def stop(self):
        self.p.stdin.close()
        self.p.wait(10)


write_config({"echo": ECHO, "slow": SLOW})
d = Daemon()
ev = d.agents()
check(ev and ev["v"] == ["claude", "echo", "slow"] and ev["current"] == "claude", "démarrage : liste des agents, claude par défaut")

d.send({"cmd": "agent", "name": "echo"})
ev = d.agents()
check(ev and ev["current"] == "echo" and ev["switched"] is True, "changement vers echo annoncé")
check(open(state).read() == "echo", "choix mémorisé dans le fichier agent")
d.send({"cmd": "send", "text": "ping-123", "mode": "fast"})
text = ""
while True:
    e = d.until(lambda e: e["t"] in ("text", "done", "error"))
    if not e or e["t"] != "text":
        break
    text += e["v"]
check("ping-123" in text, "le message part vers le nouvel agent")

d.send({"cmd": "agent", "name": "rm -rf /"})
ev = d.agents()
check(ev["current"] == "echo" and ev["switched"] is False, "nom inconnu : ignoré")
check(open(state).read() == "echo", "le fichier n'a pas changé")

d.send({"cmd": "agent", "name": "slow"})
d.agents()
d.send({"cmd": "send", "text": "go", "mode": "fast"})
d.send({"cmd": "agent", "name": "echo"})
ev = d.agents()
check(ev["current"] == "slow" and ev["switched"] is False, "refusé pendant une réponse")
d.until(lambda e: e["t"] == "done")
d.stop()

d = Daemon()
check(d.agents()["current"] == "slow", "redémarrage : agent restauré")
d.stop()

write_config({"echo": ECHO})          # "slow" a disparu de la config
d = Daemon()
check(d.agents()["current"] == "claude", "agent disparu : repli sur claude")
d.send({"cmd": "agent", "name": "claude"})
ev = d.agents()
check(ev["current"] == "claude" and ev["switched"] is False, "choisir l'agent actuel ne change rien")
d.stop()

sys.exit(1 if fails else 0)
