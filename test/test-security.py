#!/usr/bin/env python3
"""Garde-fous de sécurité, sans Claude ni réseau (appelé par la CI).

Vérifie : la carte d'autorisation montre toute la commande, les ids d'historique
ne sortent pas du dossier, la liste « lecture seule » ne contient plus de
commande qui modifie, et le texte venu de l'extérieur est neutralisé.
"""
import ast
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts")
fails = []


def check(ok, label):
    print(("  ok  " if ok else "  KO  ") + label)
    if not ok:
        fails.append(label)


def load(path, names):
    """Only the named top-level functions/constants: the modules have side effects."""
    tree = ast.parse(open(os.path.join(ROOT, path)).read())
    ns = {"re": re, "os": os, "json": json, "pick": lambda fr, en: en}
    for n in tree.body:
        if (isinstance(n, ast.FunctionDef) and n.name in names) or (
                isinstance(n, ast.Assign) and any(getattr(t, "id", "") in names for t in n.targets)):
            exec(compile(ast.Module([n], []), path, "exec"), ns)
    return ns


A = load("assistant.py", {"ask_detail", "organize_detail", "valid_cid", "READONLY_BASH"})
plan = "{\"moves\": [], \"trash\": []}"
good = f"python3 /x/organize.py apply <<'EOF'\n{plan}\nEOF"
evil = f"touch /tmp/pwned; {good}"
check(A["ask_detail"]("Bash", {"command": good}).startswith("Tidy-up"), "organize apply : résumé du plan")
check(A["ask_detail"]("Bash", {"command": evil}) == evil, "commande avec du code avant organize : affichée en entier")
check(A["ask_detail"]("Bash", {"command": f"{good}\nrm -rf ~"}) == f"{good}\nrm -rf ~", "commande après le heredoc : affichée en entier")
check(not A["valid_cid"]("../../x") and not A["valid_cid"]("a/b") and A["valid_cid"]("0123456789ab"), "ids d'historique")
ro = A["READONLY_BASH"]
check(all(c not in ro for c in ("nmcli -t", "ip -br", "ip addr", "ip route", "git branch")), "pas de préfixe trop large")

W = load("iris-watch.py", {"esc"})
out = W["esc"]("hi <a href=\"x\">[click](http://e)</a>\n**bold**")
check("\n" not in out and "<a" not in out and "](" not in out and "**" not in out.replace("\\*", ""), "esc : plus de HTML ni de lien Markdown")

sys.exit(1 if fails else 0)
