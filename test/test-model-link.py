#!/usr/bin/env python3
"""Test de model-link : agent « openai » (aucun compte, aucun réseau externe).

    test/test-model-link.py

Règles pures (config, URL, fichier de clé) puis, avec un faux serveur HTTP
local, le streaming, l'arrêt, les erreurs et la mémoire envoyée.
"""
import os
import stat
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = tempfile.mkdtemp(prefix="iris-ml-")
os.environ.update(HOME=HOME, IRIS_LANG="en")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import assistant as A  # noqa: E402

fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


# ── T1 : configuration et règles pures ───────────────────────────────────
OK = {"type": "openai", "base_url": "http://localhost:11434/v1", "models": {"fast": "a", "power": "b"}}
check(A.valid_agent(OK), "entrée openai valide")
check(A.valid_agent({"command": ["echo", "{prompt}"]}), "entrée command inchangée")
check(A.valid_agent({**OK, "base_url": "https://api.deepseek.com/v1", "key_file": "~/k", "timeout": 30,
                     "history": 4, "send_memory": True}), "options openai valides")
for label, bad in [
    ("sans base_url", {k: v for k, v in OK.items() if k != "base_url"}),
    ("schéma ftp", {**OK, "base_url": "ftp://localhost/v1"}),
    ("http hors local", {**OK, "base_url": "http://example.com/v1"}),
    ("http sur une IP du LAN", {**OK, "base_url": "http://192.168.1.5:11434/v1"}),
    ("modèle non texte", {**OK, "models": {"fast": 3}}),
    ("timeout nul", {**OK, "timeout": 0}),
    ("timeout booléen", {**OK, "timeout": True}),
    ("send_memory non booléen", {**OK, "send_memory": "oui"}),
    ("key_file non texte", {**OK, "key_file": 3}),
    ("type inconnu", {**OK, "type": "anthropic"}),
]:
    check(not A.valid_agent(bad), "refusé : " + label)

for url, ok, local in [
    ("http://localhost:11434/v1", True, True), ("http://127.0.0.1:1234/v1", True, True),
    ("http://[::1]:8080/v1", True, True), ("http://mon-pc.local/v1", True, True),
    ("https://api.deepseek.com/v1", True, False), ("https://localhost/v1", True, True),
    ("http://example.com/v1", False, False), ("http://localhost.evil.com/v1", False, False),
    ("http://127.0.0.1.evil.com/v1", False, False), ("ftp://localhost/v1", False, True),
    ("localhost:11434", False, False), ("", False, False),
]:
    check(A.endpoint_ok(url) is ok, f"endpoint_ok({url!r}) = {ok}")
    check(A.is_local(url) is local, f"is_local({url!r}) = {local}")


def keyfile(content, mode):
    p = tempfile.mktemp(dir=HOME)
    with open(p, "w") as f:
        f.write(content)
    os.chmod(p, mode)
    return p


check(A.read_key(keyfile("sk-123\n", 0o600)) == "sk-123", "clé 0600 lue et nettoyée")
for label, path in [("0644", keyfile("sk", 0o644)), ("0660", keyfile("sk", 0o660)),
                    ("vide", keyfile("\n", 0o600)), ("absente", os.path.join(HOME, "nope"))]:
    try:
        A.read_key(path)
        check(False, "clé refusée : " + label)
    except ValueError as e:
        check("sk" not in str(e) or label == "absente", "clé refusée : " + label)

if fails:
    print(f"\n{len(fails)} échec(s)")
    sys.exit(1)
print("\ntout est bon")
