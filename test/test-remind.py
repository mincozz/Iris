#!/usr/bin/env python3
"""Rappels : iris-remind (add / cancel / due) et leur déclenchement par iris-watch.

HOME jetable, sans Claude ni réseau (appelé par la CI).
"""
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


home = tempfile.mkdtemp()
FILE = os.path.join(home, ".local/share/qs-assistant/reminders.json")


def remind(*args):
    r = subprocess.run(["python3", "-I", os.path.join(ROOT, "iris-remind"), *args], capture_output=True,
                       text=True, env=dict(os.environ, HOME=home, IRIS_LANG="en"))
    return r.returncode, r.stdout.strip()


def stored():
    with open(FILE) as f:
        return json.load(f)


code, out = remind("add", "+20m", "call", "Alex")
rid = out.split()[1] if out.startswith("OK ") else ""
check(code == 0 and len(rid) == 6, "add +20m : accepté, id rendu")
r = stored()[0]
check(r["text"] == "call Alex" and 1100 < r["due"] - time.time() < 1300, "texte recomposé, échéance dans ~20 min")
check(oct(os.stat(FILE).st_mode & 0o777) == "0o600", "fichier en 0600")
check(remind("add", "2099-01-01 09:00", "x")[0] == 1, "plus d'un an : refusé")
check(remind("add", "2000-01-01 09:00", "x")[0] == 1, "date passée : refusée")
check(remind("add", "demain", "x")[0] == 1, "format inconnu : refusé")
check(remind("add", "+5m", "   ")[0] == 1, "texte vide : refusé")
check(remind("add", "+5m", "x" * 201)[0] == 1, "texte trop long : refusé")
check(remind("add", "+5m", "a\nb\x1b[31mc")[0] == 0 and "\n" not in stored()[-1]["text"], "retours à la ligne aplatis")
check(len(stored()) == 2, "seuls les rappels valides sont gardés")

check(remind("cancel", "zzzzzz")[0] == 1, "cancel d'un id inconnu : erreur")
check(remind("cancel", rid)[0] == 0 and rid not in [x["id"] for x in stored()], "cancel supprime le rappel")

for _ in range(60):
    if remind("add", "+1d", "bulk")[0] == 1:
        break
check(len(stored()) == 50, "plafond de 50 rappels")

data = stored()
data[0]["due"] = time.time() - 60
with open(FILE, "w") as f:
    json.dump(data, f)
code, out = remind("due")
check(code == 0 and [x["id"] for x in json.loads(out)] == [data[0]["id"]], "due rend les rappels échus")
check(len(stored()) == 49 and remind("due")[1] == "[]", "due les supprime : une seule fois")

sys.exit(1 if fails else 0)
