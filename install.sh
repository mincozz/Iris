#!/usr/bin/env bash
# Installateur d'Iris pour un shell Quickshell.
#   ./install.sh [--prefix DIR] [--dry-run] [--no-hypr] [--uninstall] [-y]
#                [--name NOM] [--deny-read "~/.ssh,~/.gnupg"] [--reconfigure]
#                [--fast-model ID] [--power-model ID] [--ask-key "SUPER + I"] [--ask-edit-key "SUPER + SHIFT + I"]
#                [--language fr|en|auto]
#                [--ollama-model ID]... [--add-agent "nom=commande {prompt}"]... [--no-pull]
#                [--add-openai "nom=base_url,fast=ID[,power=ID][,key_file=CHEMIN]"]...
# Sans option de config et dans un terminal, l'installateur pose quelques
# questions ; avec -y ou sans terminal, il garde les défauts.
# --ollama-model : déclare l'agent « ollama » (1er modèle = rapide, 2e = puissant)
#   et télécharge ce qui manque (ollama pull ; -y ne télécharge que si l'option
#   est donnée). --add-agent : déclare une autre CLI (jamais exécutée ici).
# --add-openai : déclare un serveur compatible OpenAI (Ollama, LM Studio, DeepSeek…) ;
#   la clé reste dans key_file (chmod 600), jamais dans config.json.
# Idempotent : on peut le relancer sans risque. Chaque fichier existant
# modifié est sauvegardé en <fichier>.iris-bak (une seule fois).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
DATA="$HOME/.local/share/qs-assistant"
DRY=0; HYPR_ON=1; UNINSTALL=0; YES=0
ASK_KEY="SUPER + I"; ASK_EDIT_KEY="SUPER + SHIFT + I"; CFG_LANG=""; CFG_NAME=""; CFG_DENY=""; CFG_FAST=""; CFG_POWER=""; RECONF=0; CFG_SET=0
OLLAMA_MODELS=(); ADD_AGENTS=(); ADD_OPENAI=(); NO_PULL=0
BEGIN="// >>> iris (install.sh) >>>"; END="// <<< iris (install.sh) <<<"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)    PREFIX="$2"; shift ;;
    --dry-run)   DRY=1 ;;
    --no-hypr)   HYPR_ON=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -y|--yes)    YES=1 ;;
    --name)        CFG_NAME="$2"; CFG_SET=1; shift ;;
    --language)    CFG_LANG="$2"; CFG_SET=1; shift ;;
    --deny-read)   CFG_DENY="$2"; CFG_SET=1; shift ;;
    --fast-model)  CFG_FAST="$2"; CFG_SET=1; shift ;;
    --power-model) CFG_POWER="$2"; CFG_SET=1; shift ;;
    --ollama-model) OLLAMA_MODELS+=("$2"); shift ;;
    --add-agent)   ADD_AGENTS+=("$2"); shift ;;
    --add-openai)  ADD_OPENAI+=("$2"); shift ;;
    --no-pull)     NO_PULL=1 ;;
    --reconfigure) RECONF=1 ;;
    --ask-key)     ASK_KEY="$2"; shift ;;
    --ask-edit-key) ASK_EDIT_KEY="$2"; shift ;;
    -h|--help)   sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac; shift
done

# Couleurs seulement dans un terminal (et sans NO_COLOR) : sobres, une seule teinte d'accent.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_ACC=$'\033[1;35m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'; C_R=$'\033[0m'
else
  C_ACC=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_B=""; C_R=""
fi
STEP=0
step() { STEP=$((STEP + 1)); printf '\n%s▸ %s%s\n' "$C_ACC" "$*" "$C_R"; }
say()  { printf '%s·%s %s\n' "$C_ACC" "$C_R" "$*"; }
warn() { printf '%s!%s %s\n' "$C_WARN" "$C_R" "$*"; }
good() { printf '  %s✓%s %s\n' "$C_OK" "$C_R" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$C_ERR" "$C_R" "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  %s[dry-run] %s%s\n' "$C_DIM" "$*" "$C_R"; else "$@"; fi; }
printf '\n%s╭────────────────────────────────╮\n│  Iris · installation           │\n╰────────────────────────────────╯%s\n' "$C_ACC" "$C_R"
[ "$DRY" = 1 ] && printf '%s  simulation : rien ne sera modifié%s\n' "$C_DIM" "$C_R"

# Order matters: Quickshell reloads as soon as a QML file changes, so the components come
# first and AssistantOverlay.qml (which uses them) last, or the reload fails on a missing type.
FILES=(
  "scripts/assistant.py" "scripts/assistant-prompt.md"
  "scripts/iris-watch.py" "scripts/organize.py" "scripts/iris-ask" "scripts/iris-doctor"
  "scripts/i18n.py" "scripts/assistant-prompt.en.md" "scripts/iris-update"
  "scripts/iris-remind" "scripts/iris-pick"
  "overlays/AssistantAvatar.qml" "overlays/AssistantTabs.qml" "overlays/AssistantHome.qml" "overlays/AssistantOverlay.qml"
)

backup() { [ -e "$1" ] && [ ! -e "$1.iris-bak" ] && run cp -p "$1" "$1.iris-bak" || true; }

# ── Désinstallation ───────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  step "Désinstallation depuis $PREFIX"
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
  warn "Retire aussi à la main le bouton de Bar.qml, la règle Hyprland 'assistant-glass' et le raccourci iris-ask s'ils existent."
  exit 0
fi

# ── Prérequis ─────────────────────────────────────────────────────────────
step "Vérification des prérequis"
missing=0
need() { command -v "$1" >/dev/null 2>&1 && good "$1" || { bad "$1 — $2"; missing=1; }; }
need python3 "requis (daemon)"
need claude  "CLI Claude Code, connectée (claude login)"
need qs      "Quickshell"
need git     "alertes git"
command -v gio >/dev/null 2>&1 && good "gio" || warn "gio absent : le rangement ne pourra pas mettre à la corbeille (paquet glib2)"
[ "$missing" = 0 ] || { warn "Prérequis manquants (voir ci-dessus)."; [ "$YES" = 1 ] || { read -r -p "Continuer quand même ? [o/N] " a; [[ "$a" =~ ^[oOyY]$ ]] || exit 1; }; }
[ -d "$PREFIX" ] || { warn "$PREFIX n'existe pas : crée ton shell Quickshell d'abord (ou utilise --prefix)."; exit 1; }

# ── Copie des fichiers ────────────────────────────────────────────────────
step "Copie vers $PREFIX"
for f in "${FILES[@]}"; do
  if [ "$DRY" = 1 ]; then
    note=""; [ -e "$PREFIX/$f" ] && ! cmp -s "$SRC/$f" "$PREFIX/$f" && note=" (remplace, sauvegarde .iris-bak)"
    [ -e "$PREFIX/$f" ] || note=" (nouveau)"
    printf '  %s[dry-run] %s%s%s\n' "$C_DIM" "$f" "$note" "$C_R"; continue
  fi
  run mkdir -p "$PREFIX/$(dirname "$f")"
  if [ -e "$PREFIX/$f" ] && ! cmp -s "$SRC/$f" "$PREFIX/$f"; then backup "$PREFIX/$f"; fi
  run install -m "$([[ $f == scripts/*.py || $f == scripts/iris-ask || $f == scripts/iris-doctor || $f == scripts/iris-update || $f == scripts/iris-remind || $f == scripts/iris-pick ]] && echo 755 || echo 644)" "$SRC/$f" "$PREFIX/$f"
done

# ── État utilisateur (jamais écrasé) ──────────────────────────────────────
step "Données dans $DATA"
run mkdir -p "$DATA"; run chmod 700 "$DATA"
# Où est le clone et où Iris est installée : iris-update s'en sert pour se mettre à jour.
if [ "$DRY" = 0 ]; then
  printf '%s\n' "$SRC" > "$DATA/source"
  printf '%s\n' "$PREFIX" > "$DATA/prefix"
  git -C "$SRC" rev-parse HEAD > "$DATA/installed-rev" 2>/dev/null || rm -f "$DATA/installed-rev"
fi
[ -e "$DATA/memory.md" ]  || run cp "$SRC/integration/memory.example.md" "$DATA/memory.md"
[ -e "$DATA/watch.json" ] || run cp "$SRC/integration/watch.example.json" "$DATA/watch.json"

# ── Configuration (config.json) ───────────────────────────────────────────
# Créée à la première installation, ou refaite avec --reconfigure. Un fichier
# existant n'est jamais écrasé sans --reconfigure.
if [ -e "$DATA/config.json" ] && [ "$RECONF" = 0 ]; then
  step "Configuration"
  good "config.json existe déjà : conservé (--reconfigure pour le refaire)"
else
  if [ "$CFG_SET" = 0 ] && [ "$YES" = 0 ] && [ -t 0 ]; then
    step "Configuration (Entrée = garder la valeur par défaut)"
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in en*) dl=en ;; *) dl=fr ;; esac
    read -r -p "  Langue d'Iris (fr / en) [$dl] : " CFG_LANG
    CFG_LANG="${CFG_LANG:-$dl}"
    read -r -p "  Comment dois-je t'appeler ? " CFG_NAME
    read -r -p "  Interdire à Iris de lire ~/.ssh et ~/.gnupg (clés, secrets) ? [O/n] " a
    # shellcheck disable=SC2088  # le ~ est voulu : Iris le développe elle-même
    [[ "$a" =~ ^[nN]$ ]] || CFG_DENY="~/.ssh,~/.gnupg"
    read -r -p "  Choisir les modèles (sinon Haiku pour le courant, Sonnet pour le code) ? [o/N] " a
    if [[ "$a" =~ ^[oOyY]$ ]]; then
      read -r -p "    Modèle rapide [claude-haiku-5-5] : " CFG_FAST
      read -r -p "    Modèle puissant [claude-sonnet-5-5] : " CFG_POWER
    fi
    read -r -p "  Ajouter un agent local (Ollama) ? [o/N] " a
    if [[ "$a" =~ ^[oOyY]$ ]]; then
      read -r -p "    Modèles, séparés par des virgules (ex. llama3.2,qwen2.5-coder) : " a
      IFS=',' read -r -a OLLAMA_MODELS <<< "${a// /}"
      read -r -p "    Télécharger ceux qui manquent maintenant ? [O/n] " a
      [[ "$a" =~ ^[nN]$ ]] && NO_PULL=1
    fi
    read -r -p "  Ajouter un autre agent (Gemini, Codex…) ? [o/N] " a
    if [[ "$a" =~ ^[oOyY]$ ]]; then
      read -r -p "    Nom : " a; an="$a"
      read -r -p "    Commande, avec {prompt} là où va la question (ex. gemini -p {prompt}) : " a
      ADD_AGENTS+=("$an=$a")
    fi
  fi
  if [ -z "$CFG_LANG" ] && [ ! -e "$DATA/config.json" ]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in en*) CFG_LANG=en ;; *) CFG_LANG=fr ;; esac
  fi
  case "$CFG_LANG" in ""|fr|en|auto) ;; *) warn "langue '$CFG_LANG' inconnue : fr utilisé"; CFG_LANG=fr ;; esac
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] écriture de $DATA/config.json (nom='${CFG_NAME}', deny-read='${CFG_DENY}')"
  else
    base="$SRC/integration/config.example.json"
    [ -e "$DATA/config.json" ] && base="$DATA/config.json"
    python3 -I - "$base" "$DATA/config.json" "$CFG_NAME" "$CFG_DENY" "$CFG_FAST" "$CFG_POWER" "$CFG_LANG" <<'PY'
import json, sys
base, out, name, deny, fast, power, lang = sys.argv[1:]
try:
    cfg = json.load(open(base))
except ValueError:
    cfg = json.load(open(base.rsplit("/", 1)[0] + "/../integration/config.example.json"))
if lang:  cfg["language"] = lang
if name:  cfg["user_name"] = name.strip()
if deny:  cfg["deny_read_paths"] = [p.strip() for p in deny.split(",") if p.strip()]
if fast:  cfg.setdefault("models", {})["fast"] = fast.strip()
if power: cfg.setdefault("models", {})["power"] = power.strip()
with open(out, "w") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
    chmod 600 "$DATA/config.json"
  fi
fi

# ── Agents et modèles (--ollama-model, --add-agent) ──────────────────────
# Fonctionne aussi sur un config.json existant : seules les clés `agents` sont
# fusionnées (sauvegarde .iris-bak) ; un agent déjà déclaré est conservé.
if [ ${#OLLAMA_MODELS[@]} -gt 0 ] || [ ${#ADD_AGENTS[@]} -gt 0 ] || [ ${#ADD_OPENAI[@]} -gt 0 ]; then
  step "Agents et modèles"
  for m in "${OLLAMA_MODELS[@]}"; do
    [[ "$m" =~ ^[A-Za-z0-9._:/-]+$ ]] || { echo "modèle invalide : $m" >&2; exit 2; }
  done
  if [ ${#OLLAMA_MODELS[@]} -gt 0 ] && [ "$NO_PULL" = 0 ]; then
    if command -v ollama >/dev/null 2>&1; then
      have="$(ollama list 2>/dev/null | awk 'NR>1 {print $1}' || true)"
      for m in "${OLLAMA_MODELS[@]}"; do
        if grep -qxF -e "$m" -e "$m:latest" <<< "$have"; then good "$m déjà téléchargé"
        else run ollama pull "$m" || warn "téléchargement de $m impossible (Ollama est-il lancé ?) : relance \`ollama pull $m\`"; fi
      done
    else
      warn "ollama introuvable : installe-le (https://ollama.com), puis \`ollama pull ${OLLAMA_MODELS[0]}\`"
    fi
  fi
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] agents ajoutés à $DATA/config.json : ${OLLAMA_MODELS[*]:+ollama (${OLLAMA_MODELS[*]}) }${ADD_AGENTS[*]:-} ${ADD_OPENAI[*]:-}"
  elif [ -e "$DATA/config.json" ]; then
    backup "$DATA/config.json"
    python3 -I - "$DATA/config.json" "$RECONF" "$SRC/scripts" "$(IFS=,; echo "${OLLAMA_MODELS[*]:-}")" "${ADD_AGENTS[@]}" "${ADD_OPENAI[@]/#/openai:}" <<'PY'
import contextlib, io, json, os, re, shlex, shutil, sys
path, reconf, scripts, models, *specs = sys.argv[1:]
cfg = json.load(open(path))
agents = cfg.setdefault("agents", {})

def put(name, spec):
    if name in agents and reconf != "1":
        print(f"  ! agent « {name} » déjà déclaré : conservé (--reconfigure pour le remplacer)")
    else:
        agents[name] = spec
        print(f"  ✓ agent « {name} » déclaré")

ms = [m for m in models.split(",") if m]
if ms:
    put("ollama", {"command": ["ollama", "run", "{model}"],
                   "models": {"fast": ms[0], "power": ms[1] if len(ms) > 1 else ms[0]}, "history": 8})
def openai_spec(s):
    """nom=base_url,fast=ID[,power=ID][,key_file=CHEMIN] -> (name, spec). Validated by the daemon's own rules."""
    head, *opts = s.split(",")
    name, _, url = head.partition("=")
    opt = dict(o.partition("=")[::2] for o in opts)
    models = {k: opt[k] for k in ("fast", "power") if opt.get(k)}
    if set(opt) - {"fast", "power", "key_file"} or not models:
        sys.exit(f"--add-openai : « {s} » invalide (options : fast, power, key_file ; un modèle au moins)")
    spec = {"type": "openai", "base_url": url.strip(),
            "models": {"fast": models.get("fast") or models["power"], "power": models.get("power") or models["fast"]}}
    if opt.get("key_file"):
        spec["key_file"] = opt["key_file"]
    sys.path.insert(0, scripts)
    with contextlib.redirect_stderr(io.StringIO()):       # the daemon prints config notes at import
        import assistant
    name = name.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", name) or name == "claude" or not assistant.valid_agent(spec):
        sys.exit(f"--add-openai : « {s} » invalide (nom ≠ claude ; https://, ou http:// vers localhost seulement)")
    if "key_file" in spec and not os.path.exists(os.path.expanduser(spec["key_file"])):
        print(f"  ! {spec['key_file']} n'existe pas encore : crée-le (chmod 600) avant de choisir « {name} »")
    return name, spec


for s in specs:
    if s.startswith("openai:"):
        put(*openai_spec(s[7:]))
        continue
    name, _, cmd = s.partition("=")
    name = name.strip()
    argv = shlex.split(cmd)          # a list, never handed to a shell
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", name) or name == "claude" or not argv:
        sys.exit(f"--add-agent : « {s} » invalide (attendu nom=commande, nom ≠ claude)")
    if not shutil.which(argv[0]):
        print(f"  ! {argv[0]} introuvable pour l'instant : à installer avant de choisir « {name} »")
    put(name, {"command": argv, "models": {}, "history": 8})
with open(path, "w") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
    chmod 600 "$DATA/config.json"
  fi
fi

# ── Skills (recettes perso) : exemples copiés une fois, jamais écrasés ────
if [ ! -d "$DATA/skills" ]; then
  SK_LANG="${CFG_LANG:-}"
  [ -n "$SK_LANG" ] || SK_LANG="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("language","fr"))' "$DATA/config.json" 2>/dev/null || echo fr)"
  case "$SK_LANG" in en) ;; fr) ;; *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in en*) SK_LANG=en ;; *) SK_LANG=fr ;; esac ;; esac
  say "Skills d'exemple dans $DATA/skills ($SK_LANG)"
  run mkdir -p "$DATA/skills"
  for f in "$SRC/integration/skills/$SK_LANG/"*.md; do run cp "$f" "$DATA/skills/"; done
fi

# ── Câblage de shell.qml ──────────────────────────────────────────────────
SHELLQML="$PREFIX/shell.qml"
if [ ! -f "$SHELLQML" ]; then
  warn "Pas de shell.qml dans $PREFIX : câblage à faire à la main (voir integration/)."
elif grep -q "AssistantOverlay" "$SHELLQML"; then
  if grep -q "function prefill" "$SHELLQML"; then
    say "shell.qml contient déjà Iris : rien à faire"
  else
    # Mise à jour d'un câblage plus ancien : ajoute la fonction IPC `prefill`
    # (raccourci « joindre la sélection ») à côté de `ask`.
    say "Ajout de la fonction IPC prefill à shell.qml (sauvegarde : shell.qml.iris-bak)"
    backup "$SHELLQML"
    [ "$DRY" = 1 ] || python3 -I - "$SHELLQML" <<'PY' || warn "Impossible d'ajouter prefill automatiquement : voir integration/shell.qml.snippet"
import re, sys
p = sys.argv[1]
s = open(p).read()
m = re.search(r"^([ \t]*)function ask\(text: string\)\s*\{\s*(\w+)\.openAssistant\(\);\s*assistantOverlay\.ask\(text\)\s*\}[^\n]*\n", s, re.M)
if not m:
    sys.exit(1)
line = f"{m.group(1)}function prefill(text: string) {{ {m.group(2)}.openAssistant(); assistantOverlay.prefill(text) }}\n"
open(p, "w").write(s[:m.end()] + line + s[m.end():])
PY
  fi
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
{ind}    function prefill(text: string) {{ root.openAssistant(); assistantOverlay.prefill(text) }}
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

  # Raccourcis « envoyer la sélection à Iris » (scripts/iris-ask)
  ASK="$PREFIX/scripts/iris-ask"
  add_bind() {   # add_bind "SUPER + I" "commande" "libellé" "option à passer"
    local key="$1" cmd="$2" label="$3" opt="$4"
    if grep -rqsF "\"$cmd\"" "$HYPR" 2>/dev/null; then
      say "Raccourci « $label » déjà présent"
    elif [ -f "$HYPR/hyprland.lua" ]; then
      if python3 -I - "$HYPR" "$key" <<'PY'
import glob, re, sys
d, want = sys.argv[1:]
norm = lambda k: re.sub(r"[\s\"']|\.\.", "", k.replace("mainMod", "SUPER")).upper()
want = norm(want)
for f in glob.glob(d + "/**/*.lua", recursive=True):
    for m in re.finditer(r"hl\.bind\(\s*([^,]+?)\s*,", open(f, errors="replace").read()):
        if norm(m.group(1)) == want:
            sys.exit(0)
sys.exit(1)
PY
      then
        warn "Le raccourci « $key » semble déjà pris : relance avec $opt \"SUPER + ALT + I\" (par ex.), ou ajoute-le toi-même."
      else
        say "Raccourci $key → $label"
        backup "$HYPR/hyprland.lua"
        [ "$DRY" = 1 ] || printf '\n-- Iris : %s\nhl.bind("%s", hl.dsp.exec_cmd("%s"))\n' "$label" "$key" "$cmd" >> "$HYPR/hyprland.lua"
      fi
    else
      warn "Pour le raccourci « $label » (hyprland.conf) : bind = ${key// + /, }, exec, $cmd"
    fi
  }
  add_bind "$ASK_KEY" "$ASK" "envoyer la sélection à Iris" "--ask-key"
  add_bind "$ASK_EDIT_KEY" "$ASK --edit" "joindre la sélection et taper une consigne" "--ask-edit-key"
fi

baks="$(find "$PREFIX" "$DATA" -name '*.iris-bak' 2>/dev/null | wc -l | tr -d ' ' || true)"
printf '\n%s%s%s\n' "$C_B" "$([ "$DRY" = 1 ] && echo "Simulation terminée : rien n'a été modifié." || echo "Iris est installée.")" "$C_R"
printf '  Fichiers     %s\n  Données      %s\n  Sauvegardes  %s\n' "$PREFIX" "$DATA" "$baks fichier(s) *.iris-bak"
printf '\n%sÀ faire à la main (spécifique à ton shell, optionnel) :%s\n' "$C_B" "$C_R"
echo "  1. Bouton dans la barre : integration/Bar.qml.snippet"
echo "  2. Clic sur une alerte « Iris » ouvre le panneau : integration/NotificationToast.qml.snippet"
printf '\nPuis relance Quickshell et teste : %sqs ipc call assistant toggle%s\n' "$C_B" "$C_R"
if [ "$DRY" = 0 ]; then
  printf '\n%sMises à jour : %s/scripts/iris-update  (ou dis « mets-toi à jour » à Iris)\nDiagnostic    : %s/scripts/iris-doctor%s\n' "$C_DIM" "$PREFIX" "$PREFIX" "$C_R"
  python3 -I "$PREFIX/scripts/iris-doctor" --prefix "$PREFIX" || true
fi
