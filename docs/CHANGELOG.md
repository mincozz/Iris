# Changelog

Les versions suivent les commits de `main` ; Iris se met à jour avec `scripts/iris-update`.

## Non publié

### Ajouté
- Panneau de chat Quickshell piloté par `claude -p` (Haiku par défaut, Sonnet pour le code), avec cartes Autoriser / Refuser montrant ce qui serait écrit.
- `install.sh` interactif ou scriptable (`--language`, `--name`, `--deny-read`, …), idempotent, avec désinstallation, et `iris-doctor` (diagnostic en lecture seule).
- `iris-update` et bouton ⬇ dans le panneau (mise à jour détectée par `iris-watch`, y compris quand le clone est plus récent que l'installation).
- Alertes locales (`iris-watch`) : `git pull` (avec bouton), travail non poussé, agenda, disque, batterie, services, mises à jour, résumé du matin.
- Raccourcis `iris-ask` (envoyer la sélection) et `iris-ask --edit` (la joindre et taper une consigne).
- Skills (recettes Markdown), mémoire locale, rangement de dossiers annulable (`organize.py`).
- Français et anglais (`language` dans `config.json`), fuseau horaire de la machine.
- `AGENTS.md` / `CLAUDE.md` pour installer avec une IA ; CI (ShellCheck, compilation, test de bout en bout, Gitleaks) ; Dependabot ; `SECURITY.md`.
