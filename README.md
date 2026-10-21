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
| `integration/` | Extraits à greffer dans `shell.qml`, `Bar.qml`, `NotificationToast.qml`, règle de blur Hyprland, `watch.json` d'exemple |

## Installation

```bash
git clone git@github.com:mincozz/IRIS.git && cd IRIS
./install.sh --dry-run   # voir ce qui sera fait
./install.sh             # installer
```

Options : `--prefix DIR` (autre dossier Quickshell), `--no-hypr`, `-y` (sans question), `--uninstall`.

Dans un terminal, l'installateur pose trois questions : ton prénom, l'interdiction de lire `~/.ssh` et `~/.gnupg` (oui par défaut) et le choix des modèles. Pour scripter ou déléguer à une IA : `--name NOM`, `--deny-read "~/.ssh,~/.gnupg"`, `--fast-model ID`, `--power-model ID`. Un `config.json` existant est conservé, `--reconfigure` le refait.

L'installateur vérifie les prérequis (Quickshell, Python 3, CLI `claude` connectée, git, `gio`), copie les fichiers, crée `~/.local/share/qs-assistant/` (mémoire et `watch.json` vierges, jamais écrasés), câble `shell.qml` (bloc balisé, sauvegarde `.iris-bak`) et ajoute la règle de flou dans `hyprland.lua`. Il est relançable sans risque.

Restent à faire à la main, car ils dépendent de ton shell : le bouton dans la barre (`integration/Bar.qml.snippet`) et le clic sur une alerte (`integration/NotificationToast.qml.snippet`). L'overlay attend un objet `theme` (`ff`, `fs`, `hi()`, `barBg`…).
Contrôle : `qs ipc call assistant toggle|open|close|ask "…"`.

## Configuration

`~/.local/share/qs-assistant/config.json` (créé par l'installateur, modèle : `integration/config.example.json`). Toutes les clés sont facultatives ; une valeur invalide est ignorée (message sur stderr) et le défaut reste.

| Clé | Rôle |
|---|---|
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

`assistant-prompt.md` est le prompt par défaut (français, tutoiement) : à adapter à ton goût.

Mémoire : Iris lit `~/.local/share/qs-assistant/memory.md` et le met à jour quand tu lui demandes de retenir quelque chose. Un modèle vide est fourni dans `integration/memory.example.md`.
L'état (historique, mémoire, agenda) reste dans `~/.local/share/qs-assistant/` et n'est pas versionné.
