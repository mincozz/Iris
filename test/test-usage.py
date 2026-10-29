#!/usr/bin/env python3
"""Test des jauges de quota : lecture de `claude -p /usage` (aucun compte, aucun quota).

    test/test-usage.py

`parse_usage` sur le texte réel de la CLI, puis `fetch_usage` avec une fausse
commande `claude` : bons arguments, clés d'API retirées, échecs sans plantage.
"""
import os
import stat
import sys
import tempfile
from datetime import datetime
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = tempfile.mkdtemp(prefix="iris-usage-")
BIN = os.path.join(HOME, "bin")
os.makedirs(BIN)
os.environ.update(HOME=HOME, IRIS_LANG="en", PATH=BIN + os.pathsep + os.environ["PATH"],
                  ANTHROPIC_API_KEY="sk-must-not-leak")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import assistant as A  # noqa: E402

fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


SAMPLE = """You are currently using your subscription to power your Claude Code usage

Current session: 37% used · resets Oct 29, 7:20pm (Europe/Paris)
Current week (all models): 25% used · resets Nov 2, 4am (Europe/Paris)

What's contributing to your usage?
"""
NOW = datetime(2026, 10, 29, 12, 0, tzinfo=ZoneInfo("Europe/Paris"))

five, week, resets = A.parse_usage(SAMPLE, NOW)
check(five == 0.37 and week == 0.25, "pourcentages lus (0..1)")
check(resets == datetime(2026, 10, 29, 19, 20, tzinfo=ZoneInfo("Europe/Paris")).timestamp(),
      "heure de remise à zéro lue dans le fuseau indiqué")
check(A.parse_usage(SAMPLE.replace("7:20pm", "12am"), NOW)[2]
      == datetime(2026, 10, 29, 0, 0, tzinfo=ZoneInfo("Europe/Paris")).timestamp(), "12am = minuit")
rolled = A.parse_usage(SAMPLE.replace("Oct 29, 7:20pm", "Jan 2, 4am"),
                       datetime(2026, 12, 30, 12, 0, tzinfo=ZoneInfo("Europe/Paris")))[2]
check(rolled == datetime(2027, 1, 2, 4, 0, tzinfo=ZoneInfo("Europe/Paris")).timestamp(), "passage d'année")
check(A.parse_usage(SAMPLE.replace("37%", "100%"), NOW)[0] == 1.0, "100 % = 1.0")
check(A.parse_usage(SAMPLE.replace(" · resets Oct 29, 7:20pm (Europe/Paris)", ""), NOW)[2] == 0,
      "sans remise à zéro : 0 (inconnue)")
check(A.parse_usage(SAMPLE.replace("(Europe/Paris)", "(Nulle/Part)"), NOW)[2] == 0, "fuseau inconnu : 0")
check(A.parse_usage("rien d'utile", NOW) is None, "texte non reconnu : None")
check(A.parse_usage("Current session: 37% used", NOW) is None, "semaine absente : None")


def fake_claude(body):
    p = os.path.join(BIN, "claude")
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(p, 0o755)


LOG = os.path.join(HOME, "argv.log")
fake_claude(f'echo "$@" "key=${{ANTHROPIC_API_KEY:-none}}" > "{LOG}"\ncat <<\'EOF\'\n{SAMPLE}EOF\n')
got = A.fetch_usage()
check(got is not None and got[0] == 0.37 and got[1] == 0.25, "fetch_usage lit la sortie de la CLI")
argv = open(LOG).read()
check("-p" in argv and "/usage" in argv and "--no-session-persistence" in argv,
      "appel : -p /usage --no-session-persistence")
check("key=none" in argv and "sk-must-not-leak" not in argv, "clé d'API retirée de l'environnement")

fake_claude("echo boom >&2\nexit 1\n")
check(A.fetch_usage() is None, "CLI en échec : None")
fake_claude("echo 'bonjour'\n")
check(A.fetch_usage() is None, "sortie inattendue : None")
os.remove(os.path.join(BIN, "claude"))
check(A.fetch_usage() is None, "CLI absente : None")

# ── Le daemon lit le quota à l'ouverture, au plus une fois par minute ─────
import json
import subprocess
import time

COUNT = os.path.join(HOME, "usage-calls")
fake_claude(f'''case "$*" in
  *"/usage"*) echo x >> "{COUNT}"; cat <<'EOF'
{SAMPLE}EOF
  ;;
  *) cat >/dev/null ;;
esac
''')
data = os.path.join(HOME, ".local/share/qs-assistant")
os.makedirs(data, exist_ok=True)
p = subprocess.Popen([sys.executable, "-I", os.path.join(ROOT, "scripts/assistant.py")], stdin=subprocess.PIPE,
                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1, env=dict(os.environ))


def usage_event(timeout=10):
    end = time.time() + timeout
    while time.time() < end:
        line = p.stdout.readline()
        if not line:
            return None
        ev = json.loads(line)
        if ev.get("t") == "usage":
            return ev
    return None


p.stdin.write('{"cmd": "warm"}\n')
p.stdin.flush()
ev = usage_event()
check(ev is not None and ev["five"] == 0.37 and ev["week"] == 0.25 and ev["resets"], "warm : le quota est émis")
p.stdin.write('{"cmd": "warm"}\n')
p.stdin.flush()
time.sleep(1.5)
check(len(open(COUNT).read().split()) == 1, "second warm dans la minute : pas de nouvel appel")
p.stdin.close()
p.wait(timeout=10)

if fails:
    print(f"\n{len(fails)} échec(s)")
    sys.exit(1)
print("\ntout est bon")
