#!/usr/bin/env python3
"""Collage d'image (Ctrl+V), côté daemon, avec un faux `wl-paste` (appelé par la CI).

Vérifie : un PNG du presse-papiers est gardé (dossier 0700, fichier 0600) et
annoncé ; un presse-papiers sans image, un faux PNG ou un wl-paste absent ne
font rien ; une image trop grosse est refusée ; les fichiers de plus de
7 jours sont purgés.
"""
import json
import os
import queue
import stat
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


PNG = b"\x89PNG\r\n\x1a\n" + b"fake-image-data"
home = tempfile.mkdtemp()
bindir = tempfile.mkdtemp()
data = os.path.join(home, ".local/share/qs-assistant")
img = os.path.join(data, "attachments")
os.makedirs(img, mode=0o700)
for name, age in (("old.png", 8), ("recent.png", 6)):
    path = os.path.join(img, name)
    open(path, "wb").write(PNG)
    os.utime(path, (time.time() - age * 86400,) * 2)

# faux wl-paste : le mode est lu dans $HOME/mode
fake = os.path.join(bindir, "wl-paste")
with open(fake, "w") as f:
    f.write(f"""#!/bin/sh
case "$(cat '{home}/mode')" in
  png) printf '\\211PNG\\r\\n\\032\\nfake-image-data' ;;
  fake) printf 'not an image' ;;
  big) printf '\\211PNG\\r\\n\\032\\n'; head -c 10500000 /dev/zero ;;
  *) exit 1 ;;
esac
""")
os.chmod(fake, 0o755)


def mode(m):
    open(os.path.join(home, "mode"), "w").write(m)


mode("none")
p = subprocess.Popen(["python3", os.path.join(ROOT, "assistant.py")], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, text=True, bufsize=1,
                     env=dict(os.environ, HOME=home, IRIS_LANG="en", PATH=bindir + ":" + os.environ["PATH"]))
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(ln) for ln in p.stdout] and lines.put(None), daemon=True).start()
time.sleep(1)    # startup purge


def paste():
    """Events produced by one Ctrl+V."""
    p.stdin.write(json.dumps({"cmd": "paste_image"}) + "\n")
    p.stdin.flush()
    time.sleep(1.5)
    out = []
    while True:
        try:
            line = lines.get_nowait()
        except queue.Empty:
            return [e for e in out if e["t"] in ("image", "error")]
        if line:
            out.append(json.loads(line))


check(not os.path.exists(os.path.join(img, "old.png")) and os.path.exists(os.path.join(img, "recent.png")),
      "au démarrage : > 7 jours purgé, 6 jours conservé")
paste()          # (vide les événements du démarrage)
mode("png")
ev = paste()
check(len(ev) == 1 and ev[0]["t"] == "image", "PNG dans le presse-papiers → un événement image")
path = ev[0]["path"] if ev else ""
check(os.path.dirname(path) == img and open(path, "rb").read() == PNG, "fichier copié dans attachments/")
check(stat.S_IMODE(os.stat(path).st_mode) == 0o600 and stat.S_IMODE(os.stat(img).st_mode) == 0o700,
      "fichier en 0600, dossier en 0700")
mode("none")
check(paste() == [], "pas d'image (texte collé) → rien")
mode("fake")
check(paste() == [], "contenu qui n'est pas un PNG → rien")
mode("big")
ev = paste()
check(len(ev) == 1 and ev[0]["t"] == "error", "image > 10 Mo → erreur")
check(len(os.listdir(img)) == 2, "l'image refusée n'est pas gardée")

p.stdin.close()
p.wait(10)
sys.exit(1 if fails else 0)
