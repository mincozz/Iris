# Sécurité

## Signaler une faille

Merci de **ne pas ouvrir d'issue publique** pour une faille de sécurité.
Utilisez le signalement privé de GitHub : onglet **Security → Report a vulnerability** de ce dépôt.
Donnez de quoi reproduire (version ou commit, étapes, ce que vous observez) ; une réponse vous sera apportée dès que possible.

## Versions concernées

Seule la dernière version de la branche `main` est maintenue. Mettez à jour avec `scripts/iris-update` (ou le bouton ⬇ du panneau).

## Ce que le projet fait et ne fait pas

Iris lance la CLI `claude` sur votre machine, avec vos droits. Quelques points utiles pour juger un signalement :

- **Autorisations** : lire des fichiers et lancer des commandes en lecture seule se fait sans demander ; tout ce qui modifie quelque chose passe par une carte Autoriser / Refuser (voir `READONLY_BASH` et `ALLOWED_TOOLS` dans `scripts/assistant.py`). `sudo`, `su`, `doas`, `dd`, `mkfs` et `wipefs` sont refusés.
- **Contenu non fiable** : mails, pages web et fichiers sont traités comme des données. Une injection de prompt qui contourne les autorisations ci-dessus est une faille à signaler.
- **Images, rappels, agents** : une image collée est vérifiée (signature PNG, 10 Mo), copiée en droits 600 dans `attachments/` et supprimée après 7 jours ; un rappel est créé par `iris-remind add` derrière une carte Autoriser / Refuser, son texte est une donnée ; le changement d'agent n'accepte que les noms de `config.json`. Un agent autre que Claude (Ollama, Gemini…) n'a pas de cartes d'autorisation : ses outils suivent ses propres règles.
- **Pas un bac à sable** : `deny_read_paths` (dans `config.json`) est un garde-fou au mieux, pas une isolation.
- **Données locales** : historique, mémoire et agenda restent dans `~/.local/share/qs-assistant/` (droits 700) et ne sont jamais envoyés ailleurs que vers Claude, via la CLI.
- **Aucun secret dans le dépôt** : la CI lance Gitleaks. Si vous en voyez un, signalez-le de la même façon.

## Hors périmètre

Les failles de Claude Code, de Quickshell, de Hyprland ou de Claude lui-même sont à signaler à leurs projets respectifs.
