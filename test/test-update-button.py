#!/usr/bin/env python3
"""Test du bouton « Mettre à jour » côté daemon (appelé par test-e2e.sh).

    test-update-button.py PREFIX MARKER_FILE_REL MARKER_TEXT

Lance assistant.py de PREFIX (HOME/XDG_CONFIG_HOME déjà positionnés), envoie
une alerte « update », puis la commande update deux fois (double clic) et
vérifie : le type d'alerte survit dans l'historique, une seule mise à jour
tourne, un seul rapport arrive, le fichier attendu est installé.
"""
import json
import os
import queue
import subprocess
import sys
import threading
import time

prefix, rel, marker = sys.argv[1:4]
data = os.path.expanduser("~/.local/share/qs-assistant")
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


flag = os.path.join(data, "update-available")
with open(flag, "w") as f:      # what iris-watch writes when a new version is out
    f.write("1")

p = subprocess.Popen(["python3", os.path.join(prefix, "scripts/assistant.py")], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, text=True, bufsize=1, env=dict(os.environ, IRIS_LANG="en"))
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(ln) for ln in p.stdout] and lines.put(None), daemon=True).start()


def send(obj):
    p.stdin.write(json.dumps(obj) + "\n")
    p.stdin.flush()


def read_until(pred, timeout=90):
    end, seen = time.time() + timeout, []
    while time.time() < end:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            continue
        if line is None:
            break
        d = json.loads(line)
        seen.append(d)
        if pred(d):
            return d, seen
    return None, seen


d, _ = read_until(lambda d: d["t"] == "update_state", 15)
check(bool(d) and d["available"] is True and d["running"] is False, "au démarrage : mise à jour disponible signalée au panneau")
send({"cmd": "nudge", "text": "update please", "kind": "update", "action": {"id": "update", "label": "Update now"}})
d, _ = read_until(lambda d: d["t"] == "nudge")
check(bool(d) and d.get("kind") == "update" and d["action"]["id"] == "update", "l'alerte garde son type et son action")
send({"cmd": "hello"})
d, _ = read_until(lambda d: d["t"] == "conversation")
check(bool(d) and [m.get("kind") for m in d["messages"]][-1:] == ["update"]
      and d["messages"][-1]["action"]["id"] == "update", "l'historique garde le type et l'action")
send({"cmd": "update"})
send({"cmd": "update"})
d, _ = read_until(lambda d: d["t"] == "update_done")
check(bool(d) and d["ok"] is True, "update_done ok=True")
st, rest = read_until(lambda d: d["t"] == "update_state", 15)
check(bool(st) and st["available"] is False, "après la mise à jour : plus de pastille (available=False)")
_, rest = read_until(lambda d: d["t"] == "update_done", 3)
check(not any(o["t"] == "update_done" for o in rest), "un seul rapport malgré le double clic")
check(not os.path.exists(flag), "fichier update-available retiré")
p.stdin.close()
p.wait(10)
check(marker in open(os.path.join(prefix, rel)).read(), "la nouveauté est installée")
check(not os.path.exists(os.path.join(data, "update-running")), "drapeau « en cours » retiré")
check(not os.path.exists(os.path.join(data, "update-result")), "résultat consommé")
sys.exit(1 if fails else 0)
