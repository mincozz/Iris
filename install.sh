#!/usr/bin/env bash
# Installateur d'Iris pour un shell Quickshell.
#   ./install.sh [--prefix DIR] [--dry-run] [--no-hypr] [--uninstall] [-y]
# Idempotent : on peut le relancer sans risque. Chaque fichier existant
# modifié est sauvegardé en <fichier>.iris-bak (une seule fois).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
DATA="$HOME/.local/share/qs-assistant"
DRY=0; HYPR_ON=1; UNINSTALL=0; YES=0
BEGIN="// >>> iris (install.sh) >>>"; END="// <<< iris (install.sh) <<<"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)    PREFIX="$2"; shift ;;
    --dry-run)   DRY=1 ;;
    --no-hypr)   HYPR_ON=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -y|--yes)    YES=1 ;;
    -h|--help)   sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac; shift
done

say()  { printf '\033[1;35m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

FILES=(
  "overlays/AssistantOverlay.qml" "overlays/AssistantAvatar.qml"
  "scripts/assistant.py" "scripts/assistant-prompt.md"
  "scripts/iris-watch.py" "scripts/organize.py"
  "assets/iris.png" "assets/iris-alpha.png"
)

backup() { [ -e "$1" ] && [ ! -e "$1.iris-bak" ] && run cp -p "$1" "$1.iris-bak" || true; }

# ── Désinstallation ───────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  say "Désinstallation depuis $PREFIX"
  for f in "${FILES[@]}"; do run rm -f "$PREFIX/$f"; done
  if [ -f "$PREFIX/shell.qml" ] && grep -qF "$BEGIN" "$PREFIX/shell.qml"; then
    say "Retrait du bloc Iris de shell.qml"
    [ "$DRY" = 1 ] || python3 -I - "$PREFIX/shell.qml" "$BEGIN" "$END" <<'PY'
import re, sys
p, b, e = sys.argv[1:]
s = open(p).read()
s = re.sub(r"[ \t]*" + re.escape(b) + r".*?" + re.escape(e) + r"\n?", "", s, flags=re.S)
open(p, "w").write(s)
PY
  fi
  warn "Ton état (mémoire, historique) reste dans $DATA : supprime-le à la main si tu veux."
  warn "Retire aussi à la main le bouton de Bar.qml et la règle Hyprland 'assistant-glass' s'ils existent."
  exit 0
fi

# ── Prérequis ─────────────────────────────────────────────────────────────
say "Vérification des prérequis"
missing=0
need() { command -v "$1" >/dev/null 2>&1 && echo "  ✓ $1" || { echo "  ✗ $1 — $2"; missing=1; }; }
need python3 "requis (daemon)"
need claude  "CLI Claude Code, connectée (claude login)"
need qs      "Quickshell"
need git     "alertes git"
command -v gio >/dev/null 2>&1 && echo "  ✓ gio" || warn "gio absent : le rangement ne pourra pas mettre à la corbeille (paquet glib2)"
[ "$missing" = 0 ] || { warn "Prérequis manquants (voir ci-dessus)."; [ "$YES" = 1 ] || { read -r -p "Continuer quand même ? [o/N] " a; [[ "$a" =~ ^[oOyY]$ ]] || exit 1; }; }
[ -d "$PREFIX" ] || { warn "$PREFIX n'existe pas : crée ton shell Quickshell d'abord (ou utilise --prefix)."; exit 1; }

# ── Copie des fichiers ────────────────────────────────────────────────────
say "Copie vers $PREFIX"
for f in "${FILES[@]}"; do
  run mkdir -p "$PREFIX/$(dirname "$f")"
  if [ -e "$PREFIX/$f" ] && ! cmp -s "$SRC/$f" "$PREFIX/$f"; then backup "$PREFIX/$f"; fi
  run install -m "$([[ $f == scripts/*.py ]] && echo 755 || echo 644)" "$SRC/$f" "$PREFIX/$f"
done

# ── État utilisateur (jamais écrasé) ──────────────────────────────────────
say "Données dans $DATA"
run mkdir -p "$DATA"; run chmod 700 "$DATA"
[ -e "$DATA/memory.md" ]  || run cp "$SRC/integration/memory.example.md" "$DATA/memory.md"
[ -e "$DATA/watch.json" ] || run cp "$SRC/integration/watch.example.json" "$DATA/watch.json"
[ -e "$DATA/config.json" ] || run cp "$SRC/integration/config.example.json" "$DATA/config.json"

# ── Câblage de shell.qml ──────────────────────────────────────────────────
SHELLQML="$PREFIX/shell.qml"
if [ ! -f "$SHELLQML" ]; then
  warn "Pas de shell.qml dans $PREFIX : câblage à faire à la main (voir integration/)."
elif grep -q "AssistantOverlay" "$SHELLQML"; then
  say "shell.qml contient déjà Iris : rien à faire"
else
  say "Câblage de shell.qml (sauvegarde : shell.qml.iris-bak)"
  backup "$SHELLQML"
  [ "$DRY" = 1 ] || python3 -I - "$SHELLQML" "$BEGIN" "$END" <<'PY'
import re, sys
p, b, e = sys.argv[1:]
s = open(p).read()
m = re.search(r"^([ \t]*)id:\s*root\b.*$", s, re.M)
if not m:
    sys.exit("shell.qml : pas de racine 'id: root' — câblage manuel nécessaire (integration/shell.qml.snippet)")
ind = m.group(1)
extra = ""
if not re.search(r"\bconfigDir\b", s):
    extra += f"{ind}property string configDir: Quickshell.shellDir\n"
if not re.search(r"\bhomeDir\b", s):
    extra += f"{ind}property string homeDir: Quickshell.env(\"HOME\")\n"
props = f"""
{ind}{b}
{ind}property bool   assistantOpen: false
{ind}property string assistantMood: "idle"   // idle | thinking | talking
{ind}property int    assistantUnread: 0
{extra.rstrip(chr(10))}
{ind}function openAssistant()   {{ assistantOpen = true }}
{ind}function closeAssistant()  {{ assistantOpen = false }}
{ind}function toggleAssistant() {{ assistantOpen = !assistantOpen }}
{ind}IpcHandler {{
{ind}    target: "assistant"
{ind}    function toggle() {{ root.toggleAssistant() }}
{ind}    function open()   {{ root.openAssistant()   }}
{ind}    function close()  {{ root.closeAssistant()  }}
{ind}    function ask(text: string) {{ root.openAssistant(); assistantOverlay.ask(text) }}
{ind}    function reveal(path: string) {{ assistantOverlay.openLink("iris-file:" + encodeURIComponent(path)) }}
{ind}}}
{ind}AssistantOverlay {{ id: assistantOverlay; shellRoot: root; theme: theme }}
{ind}{e}
"""
s = s[:m.end()] + "\n" + props.rstrip("\n") + s[m.end():]
if not re.search(r'^import\s+"\./?overlays/?"', s, re.M):
    imps = list(re.finditer(r"^import .*$", s, re.M))
    if imps:
        i = imps[-1].end()
        s = s[:i] + '\nimport "./overlays"' + s[i:]
    else:
        s = 'import "./overlays"\n' + s
open(p, "w").write(s)
PY
  grep -q "import Quickshell.Io" "$SHELLQML" || warn "shell.qml n'importe pas Quickshell.Io (IpcHandler) : ajoute 'import Quickshell.Io'."
  grep -qE "id:\s*theme" "$SHELLQML" || warn "Pas d'objet 'id: theme' dans shell.qml : l'overlay attend un thème avec : bg, fg, ff, fs, primary, secondary, tertiary, lavender, light, outline, txt2, error, warn."
fi

# ── Hyprland : flou derrière le panneau ───────────────────────────────────
if [ "$HYPR_ON" = 1 ]; then
  RULE='hl.layer_rule({ name = "assistant-glass", match = { namespace = "^quickshell-assistant$" }, no_anim = true, blur = true, ignore_alpha = 0.1 })'
  if grep -rqs "quickshell-assistant" "$HYPR" 2>/dev/null; then
    say "Règle Hyprland déjà présente"
  elif [ -f "$HYPR/hyprland.lua" ]; then
    say "Ajout de la règle de flou dans hyprland.lua"
    backup "$HYPR/hyprland.lua"
    [ "$DRY" = 1 ] || printf '\n-- Iris : flou derrière le panneau\n%s\n' "$RULE" >> "$HYPR/hyprland.lua"
  else
    warn "Config Hyprland au format .conf : ajoute (selon ta version) par ex.  layerrule = blur, quickshell-assistant  et  layerrule = ignorealpha 0.1, quickshell-assistant"
  fi
fi

echo
say "Terminé. Il reste 2 étapes à la main (spécifiques à ton shell) :"
echo "  1. Bouton dans la barre : integration/Bar.qml.snippet  (optionnel : le panneau marche sans)"
echo "  2. Clic sur une alerte « Iris » ouvre le panneau : integration/NotificationToast.qml.snippet (optionnel)"
echo "Puis relance Quickshell et teste :  qs ipc call assistant toggle"
