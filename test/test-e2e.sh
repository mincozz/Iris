#!/usr/bin/env bash
# Test de bout en bout d'Iris sur un shell Quickshell minimal et un HOME jetable.
#   test/test-e2e.sh [--with-claude] [--no-gui] [--keep]
#
# Tout se passe dans $IRIS_TEST_DIR (défaut /tmp/iris-e2e) : ton vrai shell et
# ton vrai ~/.local/share/qs-assistant ne sont pas touchés.
#   --with-claude  lie TON ~/.claude à l'instance de test et envoie un message
#                  Haiku minuscule (consomme un peu de ton quota). Sans cette
#                  option, aucun compte n'est utilisé et aucun message envoyé.
#   --no-gui       n'ouvre pas Quickshell (vérifie seulement l'installation)
#   --keep         garde le dossier de test à la fin
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="${IRIS_TEST_DIR:-/tmp/iris-e2e}"
CLAUDE=0; GUI=1; KEEP=0
for a in "$@"; do case "$a" in
  --with-claude) CLAUDE=1 ;; --no-gui) GUI=0 ;; --keep) KEEP=1 ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "option inconnue : $a" >&2; exit 2 ;; esac; done

PASS=0; FAIL=0; QSPID=""
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko()   { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
step() { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
check(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }

cleanup() {
  [ -n "$QSPID" ] && kill "$QSPID" 2>/dev/null
  if [ "$KEEP" = 0 ]; then
    case "$T" in /tmp/*) rm -rf "$T" ;; esac
  else echo "Dossier conservé : $T"; fi
}
trap cleanup EXIT

# ── 0. Préparation ────────────────────────────────────────────────────────
step "Préparation dans $T"
case "$T" in /tmp/*) ;; *) echo "IRIS_TEST_DIR doit être sous /tmp" >&2; exit 2 ;; esac
rm -rf "$T"; mkdir -p "$T/home/.config" "$T/qs"
cp "$SRC/test/shell.qml" "$T/qs/shell.qml"
if [ "$CLAUDE" = 1 ]; then
  command -v claude >/dev/null || { ko "claude introuvable (retire --with-claude)"; exit 1; }
  ln -s "$HOME/.claude" "$T/home/.claude"
  [ -e "$HOME/.claude.json" ] && ln -s "$HOME/.claude.json" "$T/home/.claude.json"
fi
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config"
DATA="$HOME/.local/share/qs-assistant"
INST=("$SRC/install.sh" --prefix "$T/qs" --no-hypr -y --name "Testeur" --deny-read "~/.ssh,~/.gnupg")

# ── 1. Installation ───────────────────────────────────────────────────────
step "Installation"
check "dry-run sans erreur"           "${INST[0]}" "${INST[@]:1}" --dry-run
check "dry-run n'écrit rien"          test ! -e "$T/qs/overlays"
check "installation sans erreur"      "${INST[@]}"
for f in overlays/AssistantOverlay.qml overlays/AssistantAvatar.qml scripts/assistant.py \
         scripts/assistant-prompt.md scripts/iris-watch.py scripts/organize.py; do
  check "fichier copié : $f" test -f "$T/qs/$f"
done
check "shell.qml câblé (bloc balisé)"  grep -q ">>> iris (install.sh)" "$T/qs/shell.qml"
check "import \"./overlays\" ajouté"    grep -q 'import "./overlays"' "$T/qs/shell.qml"
check "configDir et homeDir définis"   bash -c "grep -q 'configDir' '$T/qs/shell.qml' && grep -q 'homeDir' '$T/qs/shell.qml'"
check "mémoire vierge créée"           test -f "$DATA/memory.md"
check "config.json créé et valide"     python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$DATA/config.json"
check "config : nom et dossiers interdits" python3 -I -c "import json,sys; c=json.load(open(sys.argv[1])); assert c['user_name']=='Testeur' and c['deny_read_paths']==['~/.ssh','~/.gnupg']" "$DATA/config.json"
check "dossier de données en 700"      test "$(stat -c %a "$DATA")" = 700
sum1="$(cat "$T/qs/shell.qml" "$DATA/memory.md" | md5sum)"
"${INST[@]}" >/dev/null 2>&1
sum2="$(cat "$T/qs/shell.qml" "$DATA/memory.md" | md5sum)"
[ "$sum1" = "$sum2" ] && ok "2e installation idempotente" || ko "2e installation a modifié des fichiers"
check "scripts Python compilent"       python3 -I -m py_compile "$T/qs/scripts/assistant.py" "$T/qs/scripts/iris-watch.py" "$T/qs/scripts/organize.py"
if command -v qmllint >/dev/null; then
  qmllint "$T/qs/overlays/AssistantAvatar.qml" >/dev/null 2>&1 && ok "qmllint avatar" || echo "  · qmllint avatar : avertissements (non bloquant sans modules Quickshell)"
fi

# ── 2. Démarrage de Quickshell ────────────────────────────────────────────
if [ "$GUI" = 1 ]; then
  step "Quickshell (instance de test)"
  command -v qs >/dev/null || { ko "qs introuvable"; exit 1; }
  qs -p "$T/qs" >"$T/qs.log" 2>&1 &
  QSPID=$!
  sleep 5
  kill -0 "$QSPID" 2>/dev/null && ok "l'instance tourne" || ko "l'instance s'est arrêtée"
  if grep -qiE 'error|not a type|is not defined|unavailable' "$T/qs.log"; then
    ko "erreurs QML dans le log :"; grep -iE 'error|not a type|is not defined|unavailable' "$T/qs.log" | head -8 | sed 's/^/      /'
  else ok "aucune erreur QML dans le log"; fi
  qs ipc --pid "$QSPID" show 2>/dev/null | grep -q assistant && ok "cible IPC 'assistant' exposée" || ko "cible IPC 'assistant' absente"

  step "Ouverture du panneau"
  qs ipc --pid "$QSPID" call assistant open >/dev/null 2>&1 && ok "ipc call assistant open" || ko "ipc call assistant open"
  sleep 2
  pgrep -f "$T/qs/scripts/assistant.py" >/dev/null && ok "daemon assistant.py lancé" || ko "daemon assistant.py absent"

  if [ "$CLAUDE" = 1 ]; then
    step "Message de test (Haiku, quelques tokens)"
    qs ipc --pid "$QSPID" call assistant ask "Réponds uniquement par le mot : pong" >/dev/null 2>&1
    for _ in $(seq 1 30); do
      grep -rqi pong "$DATA/history" 2>/dev/null && break; sleep 1
    done
    grep -rqi pong "$DATA/history" 2>/dev/null && ok "Iris a répondu (« pong » dans l'historique)" \
      || ko "pas de réponse en 30 s (regarde le panneau et $T/qs.log)"
  fi

  step "À vérifier à l'œil (le panneau est ouvert)"
  cat <<'TXT'
  1. Le panneau s'affiche à droite, lisible, l'avatar est animé.
  2. Demande-lui : « écris "test" dans /tmp/iris-e2e-note.txt »
     → une carte Autoriser / Refuser apparaît AVEC le contenu à écrire. Clique Refuser :
       le fichier ne doit pas exister.
  3. Demande-lui : « retiens que j'aime le thé »
     → une carte d'autorisation apparaît pour modifier memory.md (clique Autoriser, puis
       regarde le fichier).
  4. Un lien http(s) dans une réponse s'ouvre ; rien ne s'ouvre pour un autre schéma.
TXT
  read -r -p "Appuie sur Entrée quand tu as fini (ou Ctrl+C) " _
  [ ! -e /tmp/iris-e2e-note.txt ] && ok "le fichier refusé n'a pas été créé" || { ko "/tmp/iris-e2e-note.txt existe"; rm -f /tmp/iris-e2e-note.txt; }
  kill "$QSPID" 2>/dev/null; wait "$QSPID" 2>/dev/null; QSPID=""
fi

# ── 3. Désinstallation ────────────────────────────────────────────────────
step "Désinstallation"
check "uninstall sans erreur"          "$SRC/install.sh" --prefix "$T/qs" --uninstall
check "bloc Iris retiré de shell.qml"  bash -c "! grep -q 'iris (install.sh)' '$T/qs/shell.qml'"
check "fichiers Iris supprimés"        bash -c "[ ! -e '$T/qs/overlays/AssistantOverlay.qml' ] && [ ! -e '$T/qs/scripts/assistant.py' ]"

printf '\n\033[1m%d ok, %d échec(s)\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
