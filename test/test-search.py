#!/usr/bin/env python3
"""Recherche dans l'historique, côté daemon (appelé par la CI, sans Claude).

    test-search.py

Lance le daemon avec un HOME jetable contenant trois conversations, puis
vérifie : accents et casse ignorés, extrait autour de la correspondance,
requête vide = liste complète, requête sans résultat = liste vide.
"""
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


home = tempfile.mkdtemp()
hist = os.path.join(home, ".local/share/qs-assistant/history")
os.makedirs(hist)
now = time.time()
for i, (cid, title, texts) in enumerate([
        ("aaa", "Plan de la semaine", ["Quand est la Réunion de lundi ?", "À 10h, salle B."]),
        ("bbb", "Recette", ["Comment faire des crêpes ?"]),
        ("ccc", "Réunion client", ["Rien à signaler."])]):
    msgs = [{"role": "user" if j % 2 == 0 else "assistant", "text": t} for j, t in enumerate(texts)]
    with open(os.path.join(hist, cid + ".json"), "w") as f:
        json.dump({"id": cid, "title": title, "created": now - i, "updated": now - i, "messages": msgs}, f)

p = subprocess.Popen(["python3", os.path.join(ROOT, "assistant.py")], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, text=True, bufsize=1,
                     env=dict(os.environ, HOME=home, IRIS_LANG="en"))
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(ln) for ln in p.stdout] and lines.put(None), daemon=True).start()


def search(q):
    p.stdin.write(json.dumps({"cmd": "search", "q": q}) + "\n")
    p.stdin.flush()
    end = time.time() + 20
    while time.time() < end:
        try:
            line = lines.get(timeout=0.5)
        except queue.Empty:
            continue
        if line is None:
            break
        d = json.loads(line)
        if d["t"] == "history":
            return d["v"]
    return None


ids = lambda r: sorted(c["id"] for c in r or [])

check(ids(search("reunion")) == ["aaa", "ccc"], "« reunion » trouve « Réunion » (message et titre), sans accent ni casse")
check(ids(search("CRÊPES")) == ["bbb"], "la requête avec accent et majuscules trouve « crêpes »")
r = search("salle b")
check(ids(r) == ["aaa"] and "salle B" in r[0]["snippet"], "l'extrait cite le message trouvé")
check(search("zzz") == [], "aucun résultat → liste vide")
check(ids(search("")) == ["aaa", "bbb", "ccc"], "requête vide → toute la liste")
check(ids(search("   ")) == ["aaa", "bbb", "ccc"], "requête d'espaces → toute la liste")
check(search(None) is not None and search(123) is not None, "requête invalide ignorée sans planter")
check(search("x" * 5000) == [], "requête très longue tronquée")

p.stdin.close()
p.wait(10)
sys.exit(1 if fails else 0)
