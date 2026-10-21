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
import selectors
import subprocess
import sys
import time

prefix, rel, marker = sys.argv[1:4]
data = os.path.expanduser("~/.local/share/qs-assistant")
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


p = subprocess.Popen(["python3", os.path.join(prefix, "scripts/assistant.py")], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, text=True, bufsize=1, env=dict(os.environ, IRIS_LANG="en"))
sel = selectors.DefaultSelector()
sel.register(p.stdout, selectors.EVENT_READ)


def send(obj):
    p.stdin.write(json.dumps(obj) + "\n")
    p.stdin.flush()


def read_until(pred, timeout=90):
    end, seen = time.time() + timeout, []
    while time.time() < end:
        if sel.select(0.5):
            line = p.stdout.readline()
            if not line:
                break
            d = json.loads(line)
            seen.append(d)
            if pred(d):
                return d, seen
    return None, seen


send({"cmd": "nudge", "text": "update please", "kind": "update"})
d, _ = read_until(lambda d: d["t"] == "nudge")
check(bool(d) and d.get("kind") == "update", "l'alerte garde son type « update »")
send({"cmd": "hello"})
d, _ = read_until(lambda d: d["t"] == "conversation")
check(bool(d) and [m.get("kind") for m in d["messages"]][-1:] == ["update"], "l'historique garde le type")
send({"cmd": "update"})
send({"cmd": "update"})
d, _ = read_until(lambda d: d["t"] == "update_done")
check(bool(d) and d["ok"] is True, "update_done ok=True")
_, rest = read_until(lambda d: d["t"] == "update_done", 3)
check(not any(o["t"] == "update_done" for o in rest), "un seul rapport malgré le double clic")
p.stdin.close()
p.wait(10)
check(marker in open(os.path.join(prefix, rel)).read(), "la nouveauté est installée")
check(not os.path.exists(os.path.join(data, "update-running")), "drapeau « en cours » retiré")
check(not os.path.exists(os.path.join(data, "update-result")), "résultat consommé")
sys.exit(1 if fails else 0)
