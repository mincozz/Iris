#!/usr/bin/env python3
"""Mesure des tokens d'entrée d'une conversation de 10 tours, avec les mêmes arguments que le daemon.

Demande un compte Claude et consomme du quota (modèle rapide, questions courtes, sans outil).
    python3 test/measure-tokens.py [--label avant] [--turns 10]
Sortie : un tableau par tour et le total « équivalent d'entrée »
(entrée + 0,1 × lecture de cache + 1,25 × création de cache), puis une ligne JSON dans
tasks/token-measures.jsonl pour comparer avant / après.
"""
import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import assistant as A  # noqa: E402

QUESTIONS = [
    "Salut, tu peux te présenter en une phrase ?",
    "Donne-moi un mot qui rime avec « chat ».",
    "Quelle est la capitale du Japon ?",
    "Et celle de l'Australie ?",
    "Combien font 17 fois 23 ?",
    "Résume ce qu'on s'est dit en deux phrases.",
    "Donne-moi un conseil pour bien dormir.",
    "Traduis « bonne journée » en anglais.",
    "Cite deux couleurs chaudes.",
    "Dis au revoir en cinq mots au plus.",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="mesure")
    ap.add_argument("--turns", type=int, default=10)
    args = ap.parse_args()
    cmd = ["claude", "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
           "--model", A.MODELS["fast"], "--system-prompt", A.system_prompt(False),
           "--disable-slash-commands", "--tools", A.TOOLS,
           "--allowedTools", *A.ALLOWED_TOOLS, "--disallowedTools", *A.DENIED_TOOLS, *A.mcp_deny_rules(False),
           "--no-session-persistence"]
    env = {k: v for k, v in os.environ.items() if k not in A.BILLING_ENV}
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    p = subprocess.Popen(cmd, cwd=os.path.expanduser("~"), env=env, text=True, bufsize=1,
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    rows = []
    for i, q in enumerate(QUESTIONS[:args.turns], 1):
        p.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": q},
                                  "parent_tool_use_id": None, "session_id": ""}) + "\n")
        p.stdin.flush()
        end = time.time() + 180
        for line in p.stdout:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") == "result":
                u = d.get("usage") or {}
                row = [u.get(k, 0) for k in ("input_tokens", "cache_read_input_tokens",
                                             "cache_creation_input_tokens", "output_tokens")]
                rows.append(row)
                print(f"tour {i:2d}  entrée {row[0]:6d}  cache lu {row[1]:6d}  cache créé {row[2]:6d}  sortie {row[3]:5d}")
                break
            if time.time() > end:
                break
        else:
            break
    p.stdin.close()
    p.terminate()
    if not rows:
        sys.exit("aucune réponse : claude est-il connecté ?")
    total = sum(r[0] + 0.1 * r[1] + 1.25 * r[2] for r in rows)
    print(f"\n{len(rows)} tours, équivalent d'entrée : {total:,.0f}".replace(",", " "))
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tasks", "token-measures.jsonl"), "a") as f:
        f.write(json.dumps({"label": args.label, "turns": len(rows), "rows": rows, "equiv_input": round(total)}) + "\n")


if __name__ == "__main__":
    main()
