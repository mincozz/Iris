#!/usr/bin/env python3
"""File-organising helper for Iris (the Quickshell assistant).

    organize.py scan [DIR] [--depth N]
        Read-only overview of DIR (default ~): per folder, file count, size,
        main extensions, plus big files, old files and likely duplicates.
        Compact on purpose: one call instead of dozens of `ls`.

    organize.py apply  < plan.json
        Apply a plan read from stdin:
            {"moves": [{"from": "~/a.pdf", "to": "~/Documents/Cours/a.pdf"}],
             "trash": ["~/Téléchargements/setup.exe"]}
        Parents of destinations are created. Never overwrites (an existing
        destination is skipped and reported). Trash goes through `gio trash`
        (recoverable from the file manager's trash). Every apply writes a
        journal so it can be undone.

    organize.py undo
        Revert the moves of the last apply (trash is restored by hand).

Safety: only paths inside $HOME, never the hidden top-level entries
(~/.config, ~/.ssh, ~/.local, …) nor anything inside them.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from collections import Counter, defaultdict

HOME = os.path.realpath(os.path.expanduser("~"))
JOURNAL_DIR = os.path.join(HOME, ".local/share/qs-assistant/organize-journal")


def resolve(p):
    return os.path.realpath(os.path.expanduser(p))


def check_path(p):
    """Return an error string if `p` must not be touched, else None."""
    if p == HOME or not p.startswith(HOME + os.sep):
        return "hors du dossier personnel"
    top = os.path.relpath(p, HOME).split(os.sep)[0]
    if top.startswith("."):
        return "dossier caché/système protégé"
    return None


def human(n):
    for unit in ("o", "Ko", "Mo", "Go"):
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.1f} To"


# ── scan ─────────────────────────────────────────────────────────────────
def scan(root, depth):
    root = resolve(root)
    now = time.time()
    folders = defaultdict(lambda: {"n": 0, "size": 0, "ext": Counter()})
    big, old, by_key = [], [], defaultdict(list)
    skip_dirs = {"node_modules", ".git", "__pycache__", ".venv", "venv", "target", "build", "dist"}

    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        parts = [] if rel == "." else rel.split(os.sep)
        # Hidden folders and dependency/build trees are noise for organising.
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in skip_dirs]
        bucket = os.sep.join(parts[:depth]) or "."
        for f in filenames:
            if f.startswith("."):
                continue
            path = os.path.join(dirpath, f)
            try:
                st = os.stat(path, follow_symlinks=False)
            except OSError:
                continue
            ext = os.path.splitext(f)[1].lower() or "(sans ext)"
            b = folders[bucket]
            b["n"] += 1
            b["size"] += st.st_size
            b["ext"][ext] += 1
            if st.st_size > 100 * 1024 * 1024:
                big.append((st.st_size, path))
            if now - st.st_mtime > 365 * 86400 and len(parts) <= 1:
                old.append((st.st_mtime, path))
            if st.st_size > 0:
                by_key[(f.lower(), st.st_size)].append(path)

    out = [f"# Scan de {root}", "", "## Dossiers (fichiers · taille · extensions principales)"]
    for name, b in sorted(folders.items(), key=lambda kv: -kv[1]["n"])[:60]:
        exts = ", ".join(f"{e}×{c}" for e, c in b["ext"].most_common(4))
        out.append(f"- {name}: {b['n']} · {human(b['size'])} · {exts}")
    loose = [f for f in os.listdir(root) if not f.startswith(".") and os.path.isfile(os.path.join(root, f))]
    if loose:
        out += ["", f"## Fichiers en vrac à la racine ({len(loose)})"]
        out += [f"- {f}" for f in sorted(loose)[:80]]
        if len(loose) > 80:
            out.append(f"- … et {len(loose) - 80} autres")
    if big:
        out += ["", "## Gros fichiers (>100 Mo)"]
        out += [f"- {human(s)} {p}" for s, p in sorted(big, reverse=True)[:20]]
    dups = [paths for paths in by_key.values() if len(paths) > 1]
    if dups:
        out += ["", f"## Doublons probables (même nom + même taille) : {len(dups)}"]
        for paths in dups[:20]:
            out.append("- " + " | ".join(paths))
    if old:
        out += ["", "## Non modifiés depuis plus d'un an (racine + 1 niveau)"]
        out += [f"- {time.strftime('%Y-%m-%d', time.localtime(m))} {p}" for m, p in sorted(old)[:30]]
    print("\n".join(out))


# ── apply / undo ─────────────────────────────────────────────────────────
def apply(plan):
    done, skipped, trashed = [], [], []
    for mv in plan.get("moves", []):
        src, dst = resolve(mv["from"]), resolve(mv["to"])
        err = check_path(src) or check_path(dst)
        if err:
            skipped.append(f"{mv['from']} → {mv['to']} ({err})")
        elif not os.path.lexists(src):
            skipped.append(f"{mv['from']} (introuvable)")
        elif os.path.lexists(dst):
            skipped.append(f"{mv['from']} → {mv['to']} (la destination existe déjà)")
        elif (dst + os.sep).startswith(src + os.sep):
            skipped.append(f"{mv['from']} → {mv['to']} (dossier déplacé dans lui-même)")
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.move(src, dst)
            done.append({"from": src, "to": dst})
    for t in plan.get("trash", []):
        p = resolve(t)
        err = check_path(p)
        if err or not os.path.lexists(p):
            skipped.append(f"corbeille {t} ({err or 'introuvable'})")
            continue
        r = subprocess.run(["gio", "trash", p], capture_output=True, text=True)
        if r.returncode == 0:
            trashed.append(p)
        else:
            skipped.append(f"corbeille {t} ({r.stderr.strip()[:80]})")

    if done or trashed:
        os.makedirs(JOURNAL_DIR, exist_ok=True)
        name = time.strftime("%Y%m%d-%H%M%S") + ".json"
        with open(os.path.join(JOURNAL_DIR, name), "w") as f:
            json.dump({"moves": done, "trash": trashed}, f, ensure_ascii=False, indent=1)
    print(f"{len(done)} déplacé(s), {len(trashed)} mis à la corbeille, {len(skipped)} ignoré(s).")
    for s in skipped:
        print("  ignoré :", s)
    if done or trashed:
        print("Annulable avec : organize.py undo")


def undo():
    try:
        last = sorted(f for f in os.listdir(JOURNAL_DIR) if f.endswith(".json"))[-1]
    except (OSError, IndexError):
        print("Rien à annuler.")
        return
    path = os.path.join(JOURNAL_DIR, last)
    with open(path) as f:
        j = json.load(f)
    back, failed = 0, []
    for mv in reversed(j.get("moves", [])):
        if os.path.lexists(mv["to"]) and not os.path.lexists(mv["from"]):
            os.makedirs(os.path.dirname(mv["from"]), exist_ok=True)
            shutil.move(mv["to"], mv["from"])
            back += 1
            # Remove folders the apply created and that are now empty.
            d = os.path.dirname(mv["to"])
            while d.startswith(HOME + os.sep) and d != HOME:
                try:
                    os.rmdir(d)
                except OSError:
                    break
                d = os.path.dirname(d)
        else:
            failed.append(mv["to"])
    os.rename(path, path + ".undone")
    print(f"{back} déplacement(s) annulé(s).")
    for f in failed:
        print("  impossible de remettre :", f)
    if j.get("trash"):
        print(f"{len(j['trash'])} élément(s) mis à la corbeille : à restaurer depuis la corbeille si besoin.")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    cmd = args[0]
    if cmd == "scan":
        depth = 2
        if "--depth" in args:
            i = args.index("--depth")
            depth = int(args[i + 1])
            args = args[:i] + args[i + 2:]
        scan(args[1] if len(args) > 1 else "~", depth)
    elif cmd == "apply":
        apply(json.load(sys.stdin))
    elif cmd == "undo":
        undo()
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
