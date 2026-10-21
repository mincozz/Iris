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

Prérequis : Quickshell, Python 3, la CLI `claude` connectée, `gio` (corbeille), `git`.

1. Copier `overlays/*.qml` dans `~/.config/quickshell/overlays/`, `scripts/*` dans `~/.config/quickshell/scripts/`, `assets/*` dans `~/.config/quickshell/assets/`.
2. Greffer les extraits de `integration/` :
   - `shell.qml.snippet` : propriétés/IPC + `AssistantOverlay { id: assistantOverlay; shellRoot: root; theme: theme }`
   - `Bar.qml.snippet` : bouton d'avatar dans la barre
   - `NotificationToast.qml.snippet` : un clic sur une alerte « Iris » ouvre le panneau
   - `hyprland-layer-rule.lua` : flou derrière le panneau
3. Optionnel : `integration/watch.example.json` → `~/.local/share/qs-assistant/watch.json`.
4. Contrôle : `qs ipc call assistant toggle|open|close|ask "…"`.

## Personnalisation

`assistant-prompt.md` est le prompt par défaut (français, tutoiement) : à adapter à ton goût.

Mémoire : Iris lit `~/.local/share/qs-assistant/memory.md` et le met à jour quand tu lui demandes de retenir quelque chose. Un modèle vide est fourni dans `integration/memory.example.md`.
L'état (historique, mémoire, agenda) reste dans `~/.local/share/qs-assistant/` et n'est pas versionné.
