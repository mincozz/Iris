# Iris

Assistante personnelle en pixel art qui vit dans la barre d'un shell [Quickshell](https://quickshell.org) (Arch Linux + Hyprland).
Elle s'appuie sur la CLI `claude -p` : chat, fichiers, agenda/mails via les connecteurs Claude, rangement de dossiers, et alertes spontanées (git, agenda, santé du système).

## Contenu

| Chemin | Rôle |
|---|---|
| `overlays/AssistantOverlay.qml` | Panneau de chat « liquid glass » |
| `overlays/AssistantAvatar.qml` | Avatar animé (humeur : idle / thinking / talking), aussi utilisé dans la barre |
| `scripts/assistant.py` | Daemon : pont overlay ↔ `claude -p`, choix Haiku/Sonnet, permissions (Autoriser/Refuser), historique |
| `scripts/assistant-prompt.md`, `assistant-prompt.en.md` | Prompt système d'Iris (français, anglais) |
| `scripts/i18n.py` | Choix de la langue partagé par les scripts |
| `scripts/iris-watch.py` | Alertes locales sans quota : `git pull` à faire, commits non poussés, agenda, disque/batterie/units en échec |
| `scripts/organize.py` | `scan` / `apply` / `undo` pour ranger des dossiers |
| `scripts/iris-ask` | Raccourci : envoie la sélection (ou le presse-papiers) à Iris |
| `scripts/iris-doctor` | Diagnostic : vérifie l'installation et dit quoi réparer |
| `scripts/iris-update` | Mise à jour en une commande (`git pull` + réinstallation) |
| `integration/` | Extraits à greffer dans `shell.qml`, `Bar.qml`, `NotificationToast.qml`, règle de blur Hyprland, `watch.json` d'exemple |

## Installation

```bash
git clone git@github.com:mincozz/IRIS.git && cd IRIS
./install.sh --dry-run   # voir ce qui sera fait
./install.sh             # installer
```

Options : `--prefix DIR` (autre dossier Quickshell), `--no-hypr`, `-y` (sans question), `--uninstall`.

Dans un terminal, l'installateur pose quatre questions : la langue (français ou anglais, d'après `$LANG` par défaut), ton prénom, l'interdiction de lire `~/.ssh` et `~/.gnupg` (oui par défaut) et le choix des modèles. Pour scripter ou déléguer à une IA : `--language fr|en|auto`, `--name NOM`, `--deny-read "~/.ssh,~/.gnupg"`, `--fast-model ID`, `--power-model ID`. Un `config.json` existant est conservé, `--reconfigure` le refait.

L'installateur vérifie les prérequis (Quickshell, Python 3, CLI `claude` connectée, git, `gio`), copie les fichiers, crée `~/.local/share/qs-assistant/` (mémoire et `watch.json` vierges, jamais écrasés), câble `shell.qml` (bloc balisé, sauvegarde `.iris-bak`) et ajoute la règle de flou dans `hyprland.lua`. Il est relançable sans risque.

Restent à faire à la main, car ils dépendent de ton shell : le bouton dans la barre (`integration/Bar.qml.snippet`) et le clic sur une alerte (`integration/NotificationToast.qml.snippet`). L'overlay attend un objet `theme` (`ff`, `fs`, `hi()`, `barBg`…).
Contrôle : `qs ipc call assistant toggle|open|close|ask "…"`.

## Mise à jour

```bash
~/.config/quickshell/scripts/iris-update          # ou dis « mets-toi à jour » à Iris
~/.config/quickshell/scripts/iris-update --check  # voir s'il y a du nouveau, sans rien changer
```

L'installateur retient où est ton clone ; `iris-update` fait `git pull --ff-only` dedans puis relance l'installation avec ta config actuelle (conservée). Iris le vérifie aussi toute seule toutes les 6 h et te prévient quand une version est sortie, avec un bouton **Mettre à jour** sous l'alerte. Un bouton ⬇ reste en permanence dans l'en-tête du panneau, cliquable à tout moment, avec une pastille quand une version est disponible (`"check_updates": false` dans `watch.json` pour couper les alertes). Les boutons lancent `iris-update` sans passer par Claude (aucun quota) ; le panneau peut se recharger à la fin, un message confirme le résultat. Le clone doit rester en place et sans modification locale. Les fichiers installés sont remplacés : pour personnaliser, passe par `config.json` (ou `prompt_file`).

## Alertes et résumé du matin

`iris-watch.py` tourne avec le panneau et écrit à Iris, sans quota Claude sauf la lecture de l'agenda : `git pull` à faire, travail non poussé le soir, rappels d'agenda, disque, batterie, services en échec, mises à jour. Chaque matin à partir de `morning_hour` (8 h par défaut, 5 h de fenêtre), il envoie un **résumé** : l'agenda du jour et le travail git resté en plan. Réglages dans `~/.local/share/qs-assistant/watch.json` (modèle `integration/watch.example.json`) :

| Clé | Rôle |
|---|---|
| `morning_hour` | Heure du résumé, `null` pour le couper |
| `calendar_via_claude` | `false` : Claude ne lit jamais ton agenda (seul `ics_url` sert) |
| `ics_url` | Adresse iCal secrète de ton agenda (aucun quota) |
| `remind_minutes`, `unpushed_hour`, `repo_roots`, `exclude` | Rappels d'agenda, heure de l'alerte git du soir, dossiers scannés |

Test : `python3 scripts/iris-watch.py --once morning`.

## Diagnostic

`~/.config/quickshell/scripts/iris-doctor` (lancé aussi à la fin de l'installation) vérifie les prérequis, les fichiers, le câblage de `shell.qml`, la config, les droits du dossier de données, Hyprland et l'instance Quickshell en cours. Chaque problème s'accompagne de l'action à faire. Il ne modifie rien et n'envoie rien à Claude.

## Raccourci « demande à Iris »

`scripts/iris-ask` envoie à Iris le texte sélectionné (sinon le presse-papiers) et ouvre son panneau. L'installateur ajoute `SUPER + I` à `hyprland.lua` (changeable avec `--ask-key "SUPER + SHIFT + I"`, ignoré si le raccourci est déjà pris). Pour un `hyprland.conf` : `bind = SUPER, I, exec, ~/.config/quickshell/scripts/iris-ask`. Nécessite `wl-clipboard`. `IRIS_ASK_DRY=1 iris-ask` montre ce qui serait envoyé, sans rien envoyer.

Le texte sélectionné part tel quel à Claude : évite de le déclencher sur un mot de passe.

## Configuration

`~/.local/share/qs-assistant/config.json` (créé par l'installateur, modèle : `integration/config.example.json`). Toutes les clés sont facultatives ; une valeur invalide est ignorée (message sur stderr) et le défaut reste.

| Clé | Rôle |
|---|---|
| `language` | `fr` (défaut), `en` ou `auto` (suit `$LANG`). Change le prompt, le panneau, les alertes et les messages du rangement. `IRIS_LANG=en` l'emporte sur le fichier |
| `user_name` | Comment Iris t'appelle |
| `models` | `fast` et `power` : les modèles utilisés (défaut Haiku / Sonnet) |
| `session_idle_minutes` | Inactivité avant une nouvelle conversation (défaut 30) |
| `prompt_file` | Chemin d'un prompt à toi, à la place de `assistant-prompt.md` |
| `deny_read_paths` | Dossiers que `Read`/`Grep`/`Glob` et `cat`/`head`/`tail`/`less`/`grep` ne peuvent pas lire, ex. `["~/.ssh"]`. Meilleur effort, ce n'est pas un bac à sable |
| `extra_readonly_commands` | Commandes exécutées sans demander. À toi d'être sûr qu'elles n'ont aucun effet de bord |
| `extra_denied_commands` | Commandes refusées même avec un clic |

Redémarre Iris (ou Quickshell) après une modification.

## Installation assistée par IA

`AGENTS.md` (lu aussi via `CLAUDE.md` par Claude Code) décrit la procédure, le contrat avec le shell hôte et les règles de sécurité : lance ton assistant de code dans le repo et demande-lui « installe Iris ».

## Personnalisation

Les prompts `assistant-prompt.md` (français, tutoiement) et `assistant-prompt.en.md` sont à adapter à ton goût (ou `prompt_file` pour le tien). `iris-doctor` et l'installateur restent en français.

Mémoire : Iris lit `~/.local/share/qs-assistant/memory.md` et le met à jour quand tu lui demandes de retenir quelque chose. Un modèle vide est fourni dans `integration/memory.example.md`.
L'état (historique, mémoire, agenda) reste dans `~/.local/share/qs-assistant/` et n'est pas versionné.
