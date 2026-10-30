# Reprise : où on en est, ce qu'il reste à faire

Écrit le 2026-10-29, en fin de session. À lire en premier à la reprise. Contexte : Iris (assistant Quickshell, QML + Python) doit reprendre les fonctions de <https://github.com/Louis-CFM/coucou>. Carte complète : `specs/CAPABILITY-MAP-coucou.md`.

## Règles de travail (demandées par Matis)
- **Aucune mention de l'assistant** nulle part : pas de `Co-Authored-By`, pas de « Generated with », ni dans les commits, ni dans les PR, ni dans les fichiers. Vérifier avant chaque push : `git log --format=%B origin/main..HEAD | grep -ci "co-authored\|claude code\|generated"` doit donner 0.
- **Une branche par module.** Workflow : spec (`specs/SPEC-<id>.md`) → plan (`tasks/plan-<id>.md`) → tâches (`tasks/todo-<id>.md`) → code, avec un arrêt pour validation entre chaque phase.
- **`ponytail-review` sur le diff avant le commit final d'un module** (règle de son `CLAUDE.md`). Skill `ponytail:ponytail` actif : plus petit changement qui marche, un test pour toute logique nouvelle.
- **Ne rien pousser sans demande.** Quand il dit « pousse », c'est `main` + les branches de travail (fast-forward, pas de commit de merge). Il écrit en français, veut du direct et du concis, et tranche vite via des questions à choix.
- **Captures d'écran : toujours recadrées sur la zone d'Iris** (`grim -g "X,Y WxH"`, coordonnées *logiques*, écran 2000×1250, échelle 1,6), **jamais l'écran entier** (il montre des conversations privées). Les supprimer après lecture. Ne pas dire ce qu'elles contiennent d'autre qu'Iris.
- Ne pas lire ni copier `~/.local/share/qs-assistant/` (état perso). Ne pas pousser `backup/pre-rewrite-main` ni `backup/pre-rewrite-feat` (sauvegardes à lui, historique d'avant réécriture).

## État du dépôt
- Remote : `git@github.com:mincozz/IRIS.git` (GitHub signale qu'il a déménagé vers `mincozz/Iris.git` ; `git remote set-url origin git@github.com:mincozz/Iris.git` règle l'avertissement, non fait).
- `origin/main` = `origin/feat/island-ui` = **`65c2d3a`**. Sur la branche locale `feat/island-ui` : **1 commit non poussé, `60be144`** (trombone de sélection de fichiers). C'est ce qui est **installé chez lui**.
- Branches poussées : `main`, `feat/coucou-style`, `feat/pill-merge`, `feat/model-link`, `fix/usage-gauges`, `feat/island-ui`.
- Il est sur `feat/island-ui` ; `git status` propre sauf ce fichier (non commité).
- **Son Iris installé = l'arbre de `feat/island-ui`.** Ne pas cliquer « Mettre à jour » dans le chat tant que `60be144` n'est pas poussé : ça réinstallerait `origin/main` sans le trombone.

## Fait
| Module | Branche | État |
|---|---|---|
| `model-link` : agent `type: "openai"` (Ollama, LM Studio, DeepSeek…), streaming, clé en `key_file` 0600, `install.sh --add-openai`, `iris-doctor`, pastille « distant » | `feat/model-link` | Terminé, dans `main`. 7 tâches, revue passée, essayé avec son Ollama (`qwen2.5:3b`). |
| Pastille en haut + dépôt de fichiers | `feat/pill-merge` | Le commit « Pill » n'avait jamais été fusionné dans `main` : corrigé. |
| Jauges de quota | `fix/usage-gauges` | Terminé, dans `main`. Lues avec `claude -p --no-session-persistence /usage` à l'ouverture (≤ 1 fois/min), sans appel au modèle. |
| `island-ui` T1 à T4 | `feat/island-ui` | Îlot au repos et actif, carte ouverte 640 px, onglets **Accueil / Chat** (`Ctrl+1/2`). |
| `island-ui` T7 | `feat/island-ui` | Trombone → `scripts/iris-pick` (kdialog, sinon zenity). **Non poussé.** |

## `island-ui` : reste à faire (spec `specs/SPEC-island.md`, plan `tasks/plan-island.md`, tâches `tasks/todo-island.md`)
Valeurs retenues : noir fixe, îlot qui recouvre le milieu de la barre (40 px), carte de 640 px, onglet Fichiers **supprimé** (décision du 2026-10-29), Accueil avec étapes d'outils **et** rappels.

- **T5 : Chat restylé.** Message de l'utilisateur en pastille à droite ; réponse d'Iris à gauche avec une puce « nom de l'agent » ; trois points animés pendant l'attente ; champ « Continue… » et bouton d'envoi rond ; Entrée envoie, Maj+Entrée saute une ligne. **Ne rien changer aux cartes Autoriser / Refuser, au bouton Stop, à la copie et aux liens.** Tester avec une demande qui déclenche une carte (puis Refuser). Le restyle se fait *sur place* dans `AssistantOverlay.qml` (liste de messages, ~500 lignes) : ne toucher qu'au conteneur extérieur des bulles. Un message minuscule au modèle rapide suffit pour tester.
- **T6 : Onglet Accueil** (aujourd'hui un placeholder avec le mot « Accueil »). Grande mascotte à gauche (`AssistantAvatar.size` variable), nom, agent et modèle actifs, étiquette « distant » si besoin ; liste des étapes du tour en cours ou du dernier (`Read ✓`, `Edit ⟳`, `Bash`, `Terminé`, 6 lignes au plus) construite depuis les événements déjà reçus (`toolStatus`), sans nouvelle commande daemon ; alertes non lues ; prochain rappel lu en lecture seule dans `reminders.json` par un `FileView` Quickshell (section masquée si le fichier est absent). Nouveau fichier `overlays/AssistantHome.qml` à ajouter à `FILES` (`install.sh`, `scripts/iris-doctor`, `test/test-e2e.sh`).
- **Point d'arrêt après T5**, revue avec lui.
- **T8 : Finitions.** Cibles ≥ 32 px, texte ≥ 14 px, contraste ≥ 4,5:1 (le mesurer avec un petit script sur les couleurs réelles), historique et recherche dans la carte, 20 ouvertures/fermetures sans erreur dans `qs log`. Nettoyer au passage les `light ? … : …` devenus morts (`light` vaut toujours `false`).
- **T9 : Docs et CI.** README FR/EN (aperçu, `Ctrl+1/2`, trombone), `CHANGELOG.md`, `AGENTS.md`, marquer `specs/SPEC-buddy.md` comme remplacée par `SPEC-island.md`.
- **Fin de module.** Critères de réussite de la spec tous cochés, `ponytail-review`, push seulement sur demande.

## À vérifier à la main par Matis (je ne peux pas le faire d'ici)
- Clics sur les modules de la barre à gauche et à droite de l'îlot (masque d'entrée limité à l'îlot).
- `Ctrl+1` / `Ctrl+2`, clic sur un onglet, `Échap`, clic hors de la carte.
- **Le glisser-déposer d'un fichier depuis Nautilus sur l'îlot** : jamais testé en vrai. S'il ne réagit pas, c'est un bug à instruire (le code `DropArea` attend `text/uri-list` ; la couche est maintenant `WlrLayer.Overlay` avec `exclusionMode: Ignore`).
- Le trombone : choisir 2 fichiers, annuler, ouvrir de nouveau.

## Autres modules de la carte, dans l'ordre prévu (aucun n'est commencé)
Chaque module : spec → validation → plan → validation → code, sur sa branche `feat/<id>`.
1. **`token-budget`** (dépend de `model-link`). Cible validée : **−40 % de tokens d'entrée** sur une conversation de 10 tours, compteur affiché dans la pastille, aucune régression des tests de sécurité. Pistes : prompt système allégé, cache de prompt, compactage de l'historique, routage rapide / puissant. À mesurer avant de coder (le daemon connaît déjà `last_ctx`).
2. **`hook-bridge`** : socket `$XDG_RUNTIME_DIR/iris.sock` + relais `scripts/iris-hook --agent NOM` (même idée que `coucou_agent` de Coucou, docs/AGENTS.md de leur dépôt). **Claude Code seulement pour l'instant, mais le nom d'agent est un champ** pour en ajouter d'autres sans refonte (Codex, Gemini CLI). Socket en `0600`, texte des sessions = donnée jamais instruction.
3. **`pill-active`** (dépend de `hook-bridge` et `island-ui`) : l'îlot grossit et montre une ligne par session externe (outil en cours, fichier édité `+N −M`, clic = diff).
4. **`hook-approval`** : cartes Autoriser / Refuser / Toujours pour les `PermissionRequest` et `AskUserQuestion` des agents externes, avec délai qui rend la main au terminal.
5. **`mascot-stats`** : personnalité de la mascotte (poke, étourdi, content, endormi) et statistiques locales (requêtes, tokens, temps gagné). Déjà en partie : humeurs `happy` / `sleepy`.
6. **`flow-dictation`** puis **`notetaker`**, **tout à la fin** : il n'a **pas de GPU**, donc moteur de transcription CPU à choisir à ce moment-là (whisper.cpp ou faster-whisper). Dictée = touche maintenue via un `bind` / `bindr` Hyprland, transcription locale, collage avec `wl-copy` + `wtype` (**`wtype` n'est pas installé**). Notetaker = `pw-record` sur le micro et sur le monitor du sink, audio supprimé après transcription, rappeler de prévenir les participants.

## Dette connue et points ouverts
- **`*.local` compte comme « local »** dans `is_local` (`scripts/assistant.py`) : un `http://nas.local` reçoit `memory.md` en clair sur le réseau par défaut. Il avait validé la spec, mais la revue recommande de retirer `.local` (un Ollama sur un autre PC passerait alors par `https://` ou un tunnel). Question restée sans réponse.
- **Une seule entrée `agents` invalide fait ignorer tous les agents** (`load_config`). Correctif proposé : filtrer entrée par entrée. Non fait (touche aussi les agents CLI).
- Dans `scripts/iris-pick` avec zenity, un nom de fichier contenant `|` est coupé en deux (kdialog n'a pas ce défaut ; marqué `shortcut:`).
- `integration/config.example.json` n'a volontairement pas d'exemple d'agent `openai` (le copier activerait un agent par défaut) : l'exemple est dans le README.
- Messages d'alerte « Mettre à jour » restés dans l'historique de sa conversation : inoffensifs, sauf à cliquer dessus avant d'avoir poussé.

## Pièges rencontrés (à ne pas refaire)
- **`qmllint` ne détecte pas** `Behavior on` sur une propriété `readonly`, ni un type manquant à l'exécution. Toujours installer puis lire `qs log` (`grep "ERROR\|Configuration Loaded"`). Quickshell garde l'ancienne config active quand un rechargement échoue : la barre n'est jamais coupée.
- **Ordre d'installation** : les scripts, puis les composants QML, puis `AssistantOverlay.qml` **en dernier** (Quickshell recharge dès qu'un fichier QML change ; un test e2e le garantit). Tout nouveau composant s'ajoute à `FILES` dans `install.sh`, `scripts/iris-doctor` et à la boucle de `test/test-e2e.sh`.
- **Un changement de `scripts/assistant.py` n'agit qu'au redémarrage du daemon** : `kill $(pgrep -f "^/usr/bin/python3 /home/matis/.config/quickshell/scripts/assistant.py" | head -1)` ; l'overlay le relance seul en une seconde. **Jamais `pkill -f`** avec un motif présent dans la propre commande : ça tue le shell de l'outil.
- Fenêtre `PanelWindow` plein écran : `exclusiveZone: 0` respecte la zone réservée de la barre (34 px) ; pour aller jusqu'au bord haut il faut `exclusionMode: ExclusionMode.Ignore`. Couche `WlrLayer.Overlay` pour passer au-dessus de la barre.
- Coins hauts de l'îlot : le rectangle déborde de 28 px au-dessus de l'écran (`bleed`), donc seuls les coins bas sont visibles.
- `HTTPConnection.sock` passe à `None` après `getresponse()` : garder une référence à la socket avant, sinon `stop` ne coupe rien.
- zsh : `echo ======` plante (`=` est une expansion) ; `grep -c` renvoie 1 quand il compte 0 (ne pas y voir une erreur).
- **Revenir en arrière** si l'installation casse : `git switch main && ./install.sh -y` (les `*.iris-bak` restent). Diagnostic : `scripts/iris-doctor`.
- `test/test-actions.py` et `test/test-update-button.py` demandent des arguments : ils tournent via `test/test-e2e.sh`, pas seuls.

## Commandes utiles
```
Lint       : qmllint overlays/*.qml        # 0 avertissement attendu
Shell      : shellcheck --severity=warning install.sh test/test-e2e.sh scripts/iris-ask scripts/iris-update scripts/iris-pick
Tests      : for t in agent security search remind image agent-switch model-link usage pick; do python3 -I test/test-$t.py; done
E2E        : test/test-e2e.sh --no-gui     # 87 vérifications attendues
Installer  : ./install.sh -y ; scripts/iris-doctor ; qs log | grep "ERROR\|Configuration Loaded"
Piloter    : qs ipc call assistant open | close | toggle | ask "…"     # l'état actif se voit en fermant juste après `ask`
Capture    : grim -g "680,0 640x520" /tmp/…/x.png    # recadrée, puis la supprimer
Quota      : claude -p --no-session-persistence /usage
```
Câblage de son shell : `~/.config/quickshell/glassy/shell.qml` (cible IPC `assistant`, objet `theme`). Barre : `~/.config/quickshell/bar/Bar.qml` (40 px, zone réservée 34 px, milieu libre).
