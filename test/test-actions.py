#!/usr/bin/env python3
"""Test des boutons d'action des alertes, côté daemon (appelé par test-e2e.sh).

    test-actions.py PREFIX REPO EXPECTED_SHA

REPO est un clone (sous $HOME) en retard sur son origine ; EXPECTED_SHA le
commit de l'origine. Vérifie : l'action voyage avec l'alerte et survit dans
l'historique, `git_pull` met le dépôt à jour, et les arguments douteux
(hors du dossier personnel, pas un dépôt, vide) sont refusés.
"""
import json
import os
import queue
import subprocess
import sys
import threading
import time

prefix, repo, expected = sys.argv[1:4]
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


p = subprocess.Popen(["python3", os.path.join(prefix, "scripts/assistant.py")], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, text=True, bufsize=1, env=dict(os.environ, IRIS_LANG="en"))
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(ln) for ln in p.stdout] and lines.put(None), daemon=True).start()


def send(obj):
    p.stdin.write(json.dumps(obj) + "\n")
    p.stdin.flush()


def read_until(pred, timeout=60):
    end = time.time() + timeout
    while time.time() < end:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            continue
        if line is None:
            break
        d = json.loads(line)
        if pred(d):
            return d
    return None


action = {"id": "git_pull", "arg": repo, "label": "Run git pull"}
send({"cmd": "nudge", "text": "repo behind", "kind": "git", "action": action})
d = read_until(lambda d: d["t"] == "nudge")
check(bool(d) and d.get("action") == action, "l'alerte porte son action")
send({"cmd": "hello"})
d = read_until(lambda d: d["t"] == "conversation")
check(bool(d) and d["messages"][-1].get("action") == action, "l'historique garde l'action")

send({"cmd": "action", "id": "git_pull", "arg": repo})
d = read_until(lambda d: d["t"] == "action_done")
check(bool(d) and d["ok"] is True and d["arg"] == repo, "git pull réussi")
head = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
check(head == expected, "le dépôt est bien à jour")

for label, arg in [("hors du dossier personnel", "/etc"), ("dossier sans .git", os.path.expanduser("~")),
                   ("argument vide", ""), ("argument absent", None)]:
    send({"cmd": "action", "id": "git_pull", "arg": arg})
    d = read_until(lambda d: d["t"] == "action_done", 20)
    check(bool(d) and d["ok"] is False, f"refusé : {label}")

send({"cmd": "action", "id": "rm_rf", "arg": "/"})
send({"cmd": "action", "id": "git_pull", "arg": "/etc"})
d = read_until(lambda d: d["t"] == "action_done", 20)
check(bool(d) and d["id"] == "git_pull", "une action inconnue est ignorée (aucune réponse)")

p.stdin.close()
p.wait(10)
sys.exit(1 if fails else 0)
