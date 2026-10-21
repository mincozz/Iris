# Iris

Assistante personnelle en pixel art qui vit dans la barre d'un shell [Quickshell](https://quickshell.org) (Arch Linux + Hyprland).
Elle s'appuie sur la CLI `claude -p` : chat, fichiers, agenda/mails via les connecteurs Claude, rangement de dossiers, et alertes spontanées (git, agenda, santé du système).

## Contenu

| Chemin | Rôle |
|---|---|
| `overlays/AssistantOverlay.qml` | Panneau de chat « liquid glass » |
| `overlays/AssistantAvatar.qml` | Avatar animé (humeur : idle / thinking / talking), aussi utilisé dans la barre |
| `scripts/assistant.py` | Daemon : pont overlay ↔ `claude -p`, choix Haiku/Sonnet, permissions (Autoriser/Refuser), historique |
| `scripts/assistant-prompt.md` | Prompt système d'Iris |
| `scripts/iris-watch.py` | Alertes locales sans quota : `git pull` à faire, commits non poussés, agenda, disque/batterie/units en échec |
| `scripts/organize.py` | `scan` / `apply` / `undo` pour ranger des dossiers |
| `assets/iris*.png` | Sprites |
| `integration/` | Extraits à greffer dans `shell.qml`, `Bar.qml`, `NotificationToast.qml`, règle de blur Hyprland, `watch.json` d'exemple |

## Installation

```bash
git clone git@github.com:mincozz/IRIS.git && cd IRIS
./install.sh --dry-run   # voir ce qui sera fait
./install.sh             # installer
```

Options : `--prefix DIR` (autre dossier Quickshell), `--no-hypr`, `-y` (sans question), `--uninstall`.

L'installateur vérifie les prérequis (Quickshell, Python 3, CLI `claude` connectée, git, `gio`), copie les fichiers, crée `~/.local/share/qs-assistant/` (mémoire et `watch.json` vierges, jamais écrasés), câble `shell.qml` (bloc balisé, sauvegarde `.iris-bak`) et ajoute la règle de flou dans `hyprland.lua`. Il est relançable sans risque.

Restent à faire à la main, car ils dépendent de ton shell : le bouton dans la barre (`integration/Bar.qml.snippet`) et le clic sur une alerte (`integration/NotificationToast.qml.snippet`). L'overlay attend un objet `theme` (`ff`, `fs`, `hi()`, `barBg`…).
Contrôle : `qs ipc call assistant toggle|open|close|ask "…"`.

## Personnalisation

`assistant-prompt.md` est le prompt par défaut (français, tutoiement) : à adapter à ton goût.

Mémoire : Iris lit `~/.local/share/qs-assistant/memory.md` et le met à jour quand tu lui demandes de retenir quelque chose. Un modèle vide est fourni dans `integration/memory.example.md`.
L'état (historique, mémoire, agenda) reste dans `~/.local/share/qs-assistant/` et n'est pas versionné.
