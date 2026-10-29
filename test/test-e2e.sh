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
# shellcheck disable=SC2088  # le ~ littéral est voulu (chemins écrits dans config.json)
INST=("$SRC/install.sh" --prefix "$T/qs" --no-hypr -y --name "Testeur" --language en --deny-read "~/.ssh,~/.gnupg")

# ── 1. Installation ───────────────────────────────────────────────────────
step "Installation"
check "dry-run sans erreur"           "${INST[0]}" "${INST[@]:1}" --dry-run
check "dry-run n'écrit rien"          test ! -e "$T/qs/overlays"
check "installation sans erreur"      "${INST[@]}"
for f in overlays/AssistantOverlay.qml overlays/AssistantAvatar.qml overlays/AssistantTabs.qml overlays/AssistantHome.qml scripts/assistant.py \
         scripts/assistant-prompt.md scripts/iris-watch.py scripts/organize.py scripts/iris-ask scripts/iris-doctor scripts/i18n.py scripts/assistant-prompt.en.md scripts/iris-update scripts/iris-remind scripts/iris-pick; do
  check "fichier copié : $f" test -f "$T/qs/$f"
done
check "iris-ask exécutable"           test -x "$T/qs/scripts/iris-ask"
check "iris-remind exécutable"        test -x "$T/qs/scripts/iris-remind"
check "iris-pick exécutable"          test -x "$T/qs/scripts/iris-pick"
mkdir -p "$T/home/.config/hypr" "$T/bin"
printf 'require("modules.keybinds")\n' > "$T/home/.config/hypr/hyprland.lua"
printf '#!/bin/sh\nprintf "%%s" "texte test"\n' > "$T/bin/wl-paste"; chmod +x "$T/bin/wl-paste"
check "iris-ask --edit joint la sélection (dry)" bash -c "IRIS_ASK_DRY=1 PATH='$T/bin':\$PATH '$T/qs/scripts/iris-ask' --edit | grep -q 'prefill: texte test'"
check "iris-ask envoie la sélection (dry)" bash -c "IRIS_ASK_DRY=1 PATH='$T/bin':\$PATH '$T/qs/scripts/iris-ask' | grep -q 'texte test'"
"$SRC/install.sh" --prefix "$T/qs" -y >/dev/null 2>&1
check "raccourcis Hyprland ajoutés (2, un par commande)" bash -c "[ \$(grep -c 'hl.bind.*iris-ask' '$T/home/.config/hypr/hyprland.lua') = 2 ] && grep -q 'iris-ask --edit' '$T/home/.config/hypr/hyprland.lua'"
"$SRC/install.sh" --prefix "$T/qs" -y >/dev/null 2>&1
check "raccourcis non dupliqués à la relance" bash -c "[ \$(grep -c 'hl.bind.*iris-ask' '$T/home/.config/hypr/hyprland.lua') = 2 ]"
DOC="$T/qs/scripts/iris-doctor"
check "doctor : câblage reconnu"       bash -c "python3 -I '$DOC' --prefix '$T/qs' | grep -q '✓ l.overlay est instancié'"
cp "$T/qs/shell.qml" "$T/shell.qml.ok"
python3 -I - "$T/qs/shell.qml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"AssistantOverlay\s*\{[^}]*\}", "", s))
PY
check "doctor : détecte un câblage cassé" bash -c "python3 -I '$DOC' --prefix '$T/qs' | grep -q '✗ l.overlay est instancié'"
cp "$T/shell.qml.ok" "$T/qs/shell.qml"
check "langue : le daemon suit config.json (en)" bash -c "python3 '$T/qs/scripts/assistant.py' </dev/null 2>/dev/null | head -1 | grep -q '\"lang\": \"en\"'"
check "langue : IRIS_LANG=fr l'emporte"  bash -c "IRIS_LANG=fr python3 '$T/qs/scripts/assistant.py' </dev/null 2>/dev/null | head -1 | grep -q '\"lang\": \"fr\"'"
check "langue : prompt anglais chargé"   bash -c "cd '$T/qs/scripts' && python3 -c \"import assistant; assert 'You are Iris' in assistant.system_prompt(True)\""
check "skills : exemples copiés (langue en)"  test -f "$DATA/skills/weekly-report.md"
check "skills : listés dans le prompt"       bash -c "cd '$T/qs/scripts' && python3 -c \"import assistant; p = assistant.system_prompt(True); assert '/weekly-report' in p and 'weekly-report.md' in p\""
check "langue : prompt français chargé"  bash -c "cd '$T/qs/scripts' && IRIS_LANG=fr python3 -c \"import assistant; assert 'Tu es Iris' in assistant.system_prompt(True)\""
mkdir -p "$T/proj" && ( cd "$T/proj" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && echo x > f.txt )
printf '{"morning_hour": %s, "calendar_via_claude": false, "repo_roots": ["%s"], "exclude": []}' "$((10#$(date +%H)))" "$T/proj/.." > "$DATA/watch.json"
brief1="$(python3 "$T/qs/scripts/iris-watch.py" --once morning 2>/dev/null)"
brief2="$(python3 "$T/qs/scripts/iris-watch.py" --once morning 2>/dev/null)"
check "résumé du matin : texte et git (en)" bash -c "echo '$brief1' | grep -q 'Good morning Testeur' && echo '$brief1' | grep -q 'uncommitted'"
check "fuseau : celui de la machine (TZ), pas Paris" bash -c "TZ=America/New_York python3 -I -c \"import runpy,sys,datetime as dt; sys.argv=['x']; m=runpy.run_path('$T/qs/scripts/iris-watch.py', run_name='w'); assert m['tz_name']()=='America/New_York'; assert m['_parse_dt']('20261021T090000','')[0].utcoffset()==dt.timedelta(hours=-4)\""
check "résumé du matin : une seule fois par jour" test -z "$brief2"
check "shell.qml : fonction IPC prefill"   grep -q "function prefill" "$T/qs/shell.qml"
# Mise à niveau d'un ancien câblage (sans prefill) : l'installateur l'ajoute une fois
mkdir -p "$T/qs3" && sed '/function prefill/d' "$T/qs/shell.qml" > "$T/qs3/shell.qml"
"$SRC/install.sh" --prefix "$T/qs3" --no-hypr -y >/dev/null 2>&1
check "mise à niveau : prefill ajouté à un ancien câblage" bash -c "[ \$(grep -c 'function prefill' '$T/qs3/shell.qml') = 1 ]"
"$SRC/install.sh" --prefix "$T/qs3" --no-hypr -y >/dev/null 2>&1
check "mise à niveau : pas de doublon à la relance"       bash -c "[ \$(grep -c 'function prefill' '$T/qs3/shell.qml') = 1 ]"
"$SRC/install.sh" --prefix "$T/qs" --no-hypr -y >/dev/null 2>&1
check "shell.qml câblé (bloc balisé)"  grep -q ">>> iris (install.sh)" "$T/qs/shell.qml"
check "import \"./overlays\" ajouté"    grep -q 'import "./overlays"' "$T/qs/shell.qml"
check "configDir et homeDir définis"   bash -c "grep -q 'configDir' '$T/qs/shell.qml' && grep -q 'homeDir' '$T/qs/shell.qml'"
check "mémoire vierge créée"           test -f "$DATA/memory.md"
check "config.json créé et valide"     python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$DATA/config.json"
check "config : langue, nom et dossiers interdits" python3 -I -c "import json,sys; c=json.load(open(sys.argv[1])); assert c['language']=='en' and c['user_name']=='Testeur' and c['deny_read_paths']==['~/.ssh','~/.gnupg']" "$DATA/config.json"
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

# ── 2b. Mise à jour (repo factice : origin + clone) ───────────────────────
step "Ordre d'installation"
check "AssistantOverlay.qml est copié en dernier (le reload de Quickshell a besoin des composants)" \
  python3 -I -c "import re,sys; f=re.findall(r'\"(overlays/[A-Za-z]+\.qml)\"', re.search(r'FILES=\((.*?)\n\)', open('$SRC/install.sh').read(), re.S).group(1)); assert f[-1]=='overlays/AssistantOverlay.qml', f"

step "Agents et modèles (installeur)"
# Faux ollama : `list` montre ce qui a été « téléchargé », `pull` l'ajoute et le journalise.
printf 'NAME ID\nllama3.2:latest abc\n' > "$T/ollama.have"; : > "$T/ollama.log"
cat > "$T/bin/ollama" <<SH
#!/bin/sh
case "\$1" in
  list) cat "$T/ollama.have" ;;
  pull) echo "\$2" >> "$T/ollama.log"; echo "\$2:latest x" >> "$T/ollama.have" ;;
esac
SH
chmod +x "$T/bin/ollama"
AG=("$SRC/install.sh" --prefix "$T/qs" --no-hypr -y)
PATH="$T/bin:$PATH" "${AG[@]}" --ollama-model llama3.2 --ollama-model qwen2.5-coder --add-agent "gem=sh -c cat" >/dev/null 2>&1
agent_cfg() { python3 -I -c "import json,sys; a=json.load(open('$DATA/config.json'))['agents']; $1"; }
check "agent ollama déclaré (rapide / puissant)" agent_cfg "assert a['ollama']['models']=={'fast':'llama3.2','power':'qwen2.5-coder'}"
check "agent CLI déclaré comme liste (pas de shell)" agent_cfg "assert a['gem']['command']==['sh','-c','cat']"
check "télécharge seulement ce qui manque"  test "$(cat "$T/ollama.log")" = "qwen2.5-coder"
check "config.json sauvegardé en .iris-bak"  test -f "$DATA/config.json.iris-bak"
check "agent par défaut inchangé (claude)"   bash -c "python3 -I -c \"import json; assert json.load(open('$DATA/config.json'))['agent']=='claude'\""
PATH="$T/bin:$PATH" "${AG[@]}" --ollama-model llama3.2 --ollama-model gemma3 >/dev/null 2>&1
check "relance : agent existant conservé"    agent_cfg "assert a['ollama']['models']['power']=='qwen2.5-coder'"
PATH="$T/bin:$PATH" "${AG[@]}" --no-pull --ollama-model phi4 >/dev/null 2>&1
check "--no-pull : rien téléchargé"          bash -c "! grep -q phi4 '$T/ollama.log'"
PATH="$T/bin:$PATH" "${AG[@]}" --add-agent "autre=sh -c cat" >/dev/null 2>&1
check "-y sans --ollama-model : aucun pull"  bash -c "[ \$(wc -l < '$T/ollama.log') = 2 ]"
check "modèle invalide refusé"               bash -c "! '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --ollama-model 'a;rm -rf /' >/dev/null 2>&1"
check "agent nommé claude refusé"            bash -c "! '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --add-agent 'claude=ls' >/dev/null 2>&1"
check "dry-run : ni pull ni écriture"        bash -c "before=\$(cat '$DATA/config.json'); PATH='$T/bin':\$PATH '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --dry-run --ollama-model zzz >/dev/null 2>&1; [ \"\$before\" = \"\$(cat '$DATA/config.json')\" ] && ! grep -q zzz '$T/ollama.log'"
PATH="$T/bin:$PATH" "${AG[@]}" --add-openai "deep=https://api.deepseek.com/v1,fast=deepseek-chat,power=deepseek-reasoner,key_file=~/.config/iris/deepseek.key" --add-openai "loc=http://localhost:1234/v1,fast=qwen" >/dev/null 2>&1
check "--add-openai : agent openai déclaré"       agent_cfg "assert a['deep']=={'type':'openai','base_url':'https://api.deepseek.com/v1','models':{'fast':'deepseek-chat','power':'deepseek-reasoner'},'key_file':'~/.config/iris/deepseek.key'}"
check "--add-openai : un seul modèle sert aux deux" agent_cfg "assert a['loc']['models']=={'fast':'qwen','power':'qwen'} and 'key_file' not in a['loc']"
PATH="$T/bin:$PATH" "${AG[@]}" --add-openai "deep=https://autre.example.com/v1,fast=x" >/dev/null 2>&1
check "--add-openai : agent existant conservé"      agent_cfg "assert a['deep']['base_url']=='https://api.deepseek.com/v1'"
check "--add-openai : http hors local refusé"       bash -c "! '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --add-openai 'x=http://example.com/v1,fast=m' >/dev/null 2>&1"
check "--add-openai : nom claude refusé"            bash -c "! '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --add-openai 'claude=https://a.b/v1,fast=m' >/dev/null 2>&1"
check "--add-openai : option inconnue refusée"      bash -c "! '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --add-openai 'x=https://a.b/v1,fast=m,cmd=ls' >/dev/null 2>&1"
check "--add-openai : sans modèle refusé"           bash -c "! '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --add-openai 'x=https://a.b/v1' >/dev/null 2>&1"
check "--add-openai : dry-run n'écrit rien"         bash -c "before=\$(cat '$DATA/config.json'); '$SRC/install.sh' --prefix '$T/qs' --no-hypr -y --dry-run --add-openai 'zz=https://a.b/v1,fast=m' >/dev/null 2>&1; [ \"\$before\" = \"\$(cat '$DATA/config.json')\" ]"

step "Mise à jour (iris-update)"
mkdir -p "$T/upd/src" && ( cd "$SRC" && tar --exclude=.git -cf - . ) | tar -xf - -C "$T/upd/src"
(
  cd "$T/upd/src" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -q -m "v1"
  git clone -q --bare . "$T/upd/origin.git" && cd "$T/upd" && git clone -q origin.git clone
) >/dev/null 2>&1
rm -rf "$T/qs2" && mkdir -p "$T/qs2" && cp "$T/shell.qml.ok" "$T/qs2/shell.qml"
"$T/upd/clone/install.sh" --prefix "$T/qs2" --no-hypr -y >/dev/null 2>&1
check "install depuis le clone : source mémorisée" bash -c "[ \"\$(cat '$DATA/source')\" = '$T/upd/clone' ]"
check "iris-update --check : à jour (code 0)"      "$T/qs2/scripts/iris-update" --check
( cd "$T/upd/src" && echo "# iris-update-marker" >> scripts/i18n.py && git -c user.name=t -c user.email=t@t commit -qam "v2: marker" && git push -q "$T/upd/origin.git" main ) >/dev/null 2>&1
"$T/qs2/scripts/iris-update" --check >/dev/null 2>&1; rc=$?
[ "$rc" = 10 ] && ok "iris-update --check : nouveauté détectée (code 10)" || ko "iris-update --check a renvoyé $rc au lieu de 10"
python3 "$T/qs2/scripts/iris-watch.py" --once updates > "$T/alert.json" 2>/dev/null
check "alerte « mise à jour disponible » (iris-watch)" grep -q '"kind": "update"' "$T/alert.json"
check "iris-watch écrit update-available"          test -s "$DATA/update-available"
check "iris-update installe la nouveauté"          bash -c "'$T/qs2/scripts/iris-update' -y >/dev/null 2>&1 && grep -q iris-update-marker '$T/qs2/scripts/i18n.py'"
check "update-available retiré après mise à jour"  test ! -e "$DATA/update-available"
check "config conservée après mise à jour"         python3 -I -c "import json,sys; assert json.load(open(sys.argv[1]))['user_name']=='Testeur'" "$DATA/config.json"
check "iris-update : à jour ensuite (code 0)"      "$T/qs2/scripts/iris-update" --check
( cd "$T/upd/src" && echo "# v2b" >> README.md && git -c user.name=t -c user.email=t@t commit -qam "v2b" && git push -q "$T/upd/origin.git" main ) >/dev/null 2>&1
( cd "$T/upd/clone" && echo dirty >> README.md )
check "iris-update refuse de tirer dans un clone modifié" bash -c "! '$T/qs2/scripts/iris-update' -y >/dev/null 2>&1"
( cd "$T/upd/clone" && git checkout -q README.md )
( cd "$T/upd/src" && echo "# button-marker" >> scripts/i18n.py && git -c user.name=t -c user.email=t@t commit -qam "v3: button" && git push -q "$T/upd/origin.git" main ) >/dev/null 2>&1
# Boutons d'action d'une alerte (git pull) : dépôt en retard sous $HOME
mkdir -p "$T/home/proj"
(
  cd "$T/home/proj" && git init -q -b main work && cd work && git config user.name t && git config user.email t@t \
    && echo 1 > f && git add f && git commit -q -m c1 && cd .. \
    && git clone -q --bare work origin.git && git clone -q origin.git behind \
    && cd work && echo 2 >> f && git commit -qam c2 && git push -q ../origin.git main
) >/dev/null 2>&1
want="$(git -C "$T/home/proj/work" rev-parse HEAD 2>/dev/null)"
check "boutons d'action : git pull et refus (daemon)" python3 "$SRC/test/test-actions.py" "$T/qs2" "$T/home/proj/behind" "$want"
check "bouton « Mettre à jour » (daemon)"          python3 "$SRC/test/test-update-button.py" "$T/qs2" scripts/i18n.py button-marker

# Le clone est plus récent que l'installation (poussé depuis ce clone, ou tiré à la main)
( cd "$T/upd/clone" && echo "# local-marker" >> scripts/i18n.py && git -c user.name=t -c user.email=t@t commit -qam "local only" ) >/dev/null 2>&1
"$T/qs2/scripts/iris-update" --check >/dev/null 2>&1; rc=$?
[ "$rc" = 10 ] && ok "clone plus récent que l'installation : détecté (code 10)" || ko "clone en avance : --check a renvoyé $rc au lieu de 10"
python3 "$T/qs2/scripts/iris-watch.py" --once updates > "$T/alert2.json" 2>/dev/null
check "clone en avance : alerte « mise à jour » (iris-watch)" grep -q '"kind": "update"' "$T/alert2.json"
check "clone en avance : iris-update réinstalle sans pull"  bash -c "'$T/qs2/scripts/iris-update' -y >/dev/null 2>&1 && grep -q local-marker '$T/qs2/scripts/i18n.py'"
check "clone en avance : ensuite à jour (code 0)"           "$T/qs2/scripts/iris-update" --check
( cd "$T/upd/clone" && git reset -q --hard HEAD~1 ) >/dev/null 2>&1
"$SRC/install.sh" --prefix "$T/qs" --no-hypr -y >/dev/null 2>&1

# ── 3. Désinstallation ────────────────────────────────────────────────────
step "Désinstallation"
check "uninstall sans erreur"          "$SRC/install.sh" --prefix "$T/qs" --uninstall
check "bloc Iris retiré de shell.qml"  bash -c "! grep -q 'iris (install.sh)' '$T/qs/shell.qml'"
check "fichiers Iris supprimés"        bash -c "[ ! -e '$T/qs/overlays/AssistantOverlay.qml' ] && [ ! -e '$T/qs/scripts/assistant.py' ]"

printf '\n\033[1m%d ok, %d échec(s)\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
