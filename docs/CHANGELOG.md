# Changelog

Les versions suivent les commits de `main` ; Iris se met à jour avec `scripts/iris-update`.

## Non publié

### Sécurité
- La carte Autoriser/Refuser montre toute la commande : un `organize.py apply` collé après une autre commande ne masque plus celle-ci.
- `WebSearch` demande désormais un accord (une requête peut faire sortir des données) ; `deny_read_paths` protège par défaut `~/.ssh`, `~/.gnupg`, `~/.aws` et refuse toute commande qui cite ces chemins.
- Liste « lecture seule » resserrée (`nmcli -t`, `ip -br`, `ip addr`, `git branch` ne passent plus sans accord) ; `git diff --no-index` et `journalctl --vacuum/--rotate/--flush` refusés.
- `iris-watch` neutralise le HTML/Markdown des textes venus de l'extérieur (commits, agenda) et lance git sans `fsmonitor` ni hooks ; Iris est prévenue que ces citations sont de la donnée.
- Ids d'historique validés (plus de `../`) ; les cartes montrent la taille du texte coupé et plus de champs des connecteurs.

### Ajouté
- Agent au choix : `agent` / `agents` dans `config.json` branchent n'importe quelle CLI (Gemini, Ollama, Codex…) à la place de `claude -p`, sans outils ni cartes d'autorisation.
- Changer d'agent depuis le panneau : pastille dans l'en-tête, choix mémorisé à part (`config.json` n'est jamais réécrit).
- Panneau de chat Quickshell piloté par `claude -p` (Haiku par défaut, Sonnet pour le code), avec cartes Autoriser / Refuser montrant ce qui serait écrit.
- `install.sh` interactif ou scriptable (`--language`, `--name`, `--deny-read`, …), idempotent, avec désinstallation, et `iris-doctor` (diagnostic en lecture seule).
- `iris-update` et bouton ⬇ dans le panneau (mise à jour détectée par `iris-watch`, y compris quand le clone est plus récent que l'installation).
- Alertes locales (`iris-watch`) : `git pull` (avec bouton), travail non poussé, agenda, disque, batterie, services, mises à jour, résumé du matin.
- Raccourcis `iris-ask` (envoyer la sélection) et `iris-ask --edit` (la joindre et taper une consigne).
- Skills (recettes Markdown), mémoire locale, rangement de dossiers annulable (`organize.py`).
- Français et anglais (`language` dans `config.json`), fuseau horaire de la machine.
- `AGENTS.md` / `CLAUDE.md` pour installer avec une IA ; CI (ShellCheck, compilation, test de bout en bout, Gitleaks) ; Dependabot ; `SECURITY.md`.
- Recherche dans l'historique : un champ filtre les conversations à chaque lettre (titre et messages, accents et casse ignorés) et montre un extrait.
- Rappels uniques (`iris-remind`) : « rappelle-moi dans 20 min… », carte d'autorisation, alerte à l'heure par `iris-watch`, rappel manqué envoyé au démarrage suivant.
- Images : Ctrl+V colle une capture du presse-papiers (PNG, 10 Mo au plus) avec une pastille « Image jointe » ; fichiers gardés 7 jours dans `attachments/`.
