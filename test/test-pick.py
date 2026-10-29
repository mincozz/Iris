#!/usr/bin/env python3
"""Test du sélecteur de fichiers `scripts/iris-pick` (aucune fenêtre, aucun compte).

    test/test-pick.py

De fausses commandes kdialog et zenity dans un PATH jetable : fichiers rendus un
par ligne, annulation (code 1), aucun sélecteur installé (code 127), préférence
pour kdialog, dossier de départ transmis.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "scripts/iris-pick")
HOME = tempfile.mkdtemp(prefix="iris-pick-")
BIN = os.path.join(HOME, "bin")
os.makedirs(BIN)
for tool in ("tr", "cat"):                       # what the script itself needs, and nothing else
    os.symlink(subprocess.run(["which", tool], capture_output=True, text=True).stdout.strip(), os.path.join(BIN, tool))
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


def fake(name, body):
    p = os.path.join(BIN, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(p, 0o755)


def pick(*args):
    r = subprocess.run(["/bin/sh", SCRIPT, *args], capture_output=True, text=True, timeout=20,
                       env={"PATH": BIN, "HOME": HOME})
    return r.returncode, r.stdout


check(os.access(SCRIPT, os.X_OK), "iris-pick est exécutable")

code, out = pick()
check(code == 127 and out == "", "aucun sélecteur : code 127, rien sur stdout")

ARGS = os.path.join(HOME, "args")
fake("zenity", f'echo "$@" > "{ARGS}"\nprintf "/a b/un.txt|/c/deux é.png"\n')
code, out = pick("/start")
check(code == 0 and out == "/a b/un.txt\n/c/deux é.png\n", "zenity : fichiers un par ligne (espaces et accents)")
check("--multiple" in open(ARGS).read() and "/start" in open(ARGS).read(), "zenity : sélection multiple et dossier de départ")

fake("zenity", "exit 1\n")
code, out = pick()
check(code == 1 and out == "", "zenity annulé : code 1")

fake("kdialog", f'echo "$@" > "{ARGS}"\nprintf "/x/un.txt\\n/y/deux.txt\\n"\n')
fake("zenity", "echo ne-doit-pas-etre-appele\n")
code, out = pick("/start")
check(code == 0 and out == "/x/un.txt\n/y/deux.txt\n", "kdialog préféré à zenity, fichiers un par ligne")
args = open(ARGS).read()
check("--multiple" in args and "--separate-output" in args and "/start" in args,
      "kdialog : --multiple --separate-output et dossier de départ")

fake("kdialog", "exit 1\n")
code, out = pick()
check(code == 1 and out == "", "kdialog annulé : code 1")

if fails:
    print(f"\n{len(fails)} échec(s)")
    sys.exit(1)
print("\ntout est bon")
