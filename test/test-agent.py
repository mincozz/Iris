#!/usr/bin/env python3
"""Test du backend « agent au choix » (aucun compte, aucun quota).

    test/test-agent.py

Lance le daemon dans un HOME jetable avec de faux agents (commandes `sh`) :
réponse streamée, prompt sur stdin ou dans {prompt}, {model} substitué,
historique rejoué, erreur remontée, commande introuvable, bouton stop, et repli
sur claude quand le nom de l'agent est inconnu.
"""
import json
import os
import queue
import shutil
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


class Daemon:
    def __init__(self, agent, agents):
        self.home = tempfile.mkdtemp(prefix="iris-agent-")
        data = os.path.join(self.home, ".local/share/qs-assistant")
        os.makedirs(data)
        with open(os.path.join(data, "config.json"), "w") as f:
            json.dump({"language": "en", "agent": agent, "agents": agents}, f)
        self.p = subprocess.Popen(
            [sys.executable, os.path.join(ROOT, "scripts/assistant.py")], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
            env=dict(os.environ, HOME=self.home, IRIS_LANG="en"))
        self.lines = queue.Queue()
        threading.Thread(target=lambda: [self.lines.put(ln) for ln in self.p.stdout] and self.lines.put(None),
                         daemon=True).start()

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def reply(self, text, timeout=20, then=None):
        """Sends a message; returns (text received, error or None)."""
        self.send({"cmd": "send", "text": text})
        if then:
            then()
        out, err, end = "", None, time.time() + timeout
        while time.time() < end:
            try:
                ln = self.lines.get(timeout=0.5)
            except queue.Empty:
                continue
            if ln is None:
                break
            d = json.loads(ln)
            if d["t"] == "text":
                out += d["v"]
            elif d["t"] == "error":
                err = d["v"]
            elif d["t"] == "done":
                return out, err
        return out, "timeout"

    def close(self):
        self.p.stdin.close()
        self.p.wait(10)
        err = self.p.stderr.read()
        shutil.rmtree(self.home, ignore_errors=True)
        return err


# stdin: the whole prompt (system prompt + history + message) is on stdin
d = Daemon("echo", {"echo": {"command": ["sh", "-c", "cat"], "history": 8}})
out, err = d.reply("first question")
check(err is None and "first question" in out, "le prompt arrive sur stdin et la réponse est streamée")
check("Iris" in out, "le prompt système d'Iris est joint")
out, err = d.reply("second question")
check("first question" in out and "second question" in out, "l'historique récent est rejoué")
d.close()

# {prompt} and {model} are substituted; fast model by default
d = Daemon("argv", {"argv": {"command": ["sh", "-c", 'echo "model=$1 len=${#2}"', "x", "{model}", "{prompt}"],
                            "models": {"fast": "small", "power": "big"}}})
out, err = d.reply("hello")
check(err is None and "model=small" in out and "len=0" not in out, "{model} et {prompt} sont substitués")
d.close()

# a failing agent reports its stderr
d = Daemon("bad", {"bad": {"command": ["sh", "-c", "echo boom >&2; exit 3"]}})
out, err = d.reply("hello")
check(err == "boom", "l'erreur de l'agent est remontée")
d.close()

# a missing command is an error, not a crash
d = Daemon("gone", {"gone": {"command": ["iris-no-such-command"]}})
out, err = d.reply("hello")
check(bool(err) and err != "timeout", "commande introuvable : erreur claire")
out, err = d.reply("again")
check(bool(err) and err != "timeout", "le daemon survit")
d.close()

# stop kills the process and ends the reply without an error
d = Daemon("slow", {"slow": {"command": ["sh", "-c", "echo start; sleep 30"]}})
t0 = time.time()
out, err = d.reply("hello", then=lambda: (time.sleep(1), d.send({"cmd": "stop"})))
check(err is None and time.time() - t0 < 10, "stop interrompt l'agent")
d.close()

# an unknown agent name falls back to claude, with a warning
d = Daemon("nope", {"echo": {"command": ["cat"]}})
time.sleep(1)
err = d.close()
check("not found in 'agents'" in err, "agent inconnu : repli sur claude, signalé")

# an invalid agent entry is ignored
d = Daemon("echo", {"echo": {"command": "cat"}})
time.sleep(1)
err = d.close()
check("invalid 'agents'" in err, "entrée d'agent invalide refusée")

sys.exit(1 if fails else 0)
