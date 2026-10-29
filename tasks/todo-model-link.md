# Tâches : model-link

Plan : `tasks/plan-model-link.md`. Spec : `specs/SPEC-model-link.md`.
Test principal : `python3 -I test/test-model-link.py` (faux serveur HTTP local, `HOME` jetable, sans réseau ni compte).
Commits sans co-auteur.

- [x] **T0 : Branche**
  - Acceptance : `feat/model-link` créée depuis `main` ; carte, spec et plan (`specs/*coucou*`, `specs/SPEC-model-link.md`, `tasks/*model-link.md`) commités en premier.
  - Verify : `git log --oneline main..HEAD` ; aucune ligne `Co-Authored-By` (`git log --format=%B | grep -ci co-authored` → 0).
  - Files : specs, tasks.

- [x] **T1 : Déclarer un agent `openai` (config + règles pures)**
  - Acceptance : `valid_agent()` accepte `{"type":"openai","base_url",…,"models"}` et toujours `{"command":[…]}` ; refuse `base_url` absent, schéma ni http ni https, `http://` hors local, `timeout`/`history` hors bornes. `endpoint_ok()` et `read_key()` (refus si `mode & 0o077`, fichier absent, vide) en fonctions pures. Entrée invalide ignorée avec message stderr, repli sur `claude`.
  - Verify : `python3 -I test/test-model-link.py` (tests écrits d'abord, rouges puis verts) ; `python3 -I test/test-agent.py` et `test-agent-switch.py` inchangés et verts.
  - Files : `scripts/assistant.py`, `test/test-model-link.py`.
  - Scope : S.

- [x] **T2 : Réponse en streaming + stop (tranche verticale minimale)**
  - Acceptance : `OpenAIAgent` envoie `POST {base_url}/chat/completions` (`stream: true`, `messages` = système + historique + message), émet un `text_delta` par fragment et un `result` final ; `new_agent` aiguille selon la forme de l'entrée ; `{model}` vient de `models.fast|power` ; clé envoyée en `Authorization: Bearer` ; `stop` coupe la connexion même si le serveur se tait ; fin de flux par `[DONE]` ou fermeture propre ; fragments d'un octet et `reasoning_content` gérés ; redirection refusée.
  - Verify : tests avec faux serveur : réponse multi-fragments, flux découpé octet par octet, serveur muet + stop (< 2 s), redirection refusée, en-tête d'autorisation présent.
  - Files : `scripts/assistant.py`, `test/test-model-link.py`.
  - Scope : M.

- [x] **T3 : Erreurs lisibles et délai**
  - Acceptance : connexion refusée, 401/403, 404, 429, 5xx, JSON illisible et délai sans octet (`timeout`) donnent chacun un message `pick(fr, en)` ; la clé n'apparaît ni dans le message, ni dans stderr, ni dans l'historique.
  - Verify : un test par cas ; test qui cherche la clé dans toute la sortie (stdout + stderr + fichiers `history/`).
  - Files : `scripts/assistant.py`, `test/test-model-link.py`.
  - Scope : S.

### Checkpoint : daemon complet
- [x] Tous les tests existants + `test-model-link.py` passent ; `py_compile` propre.
- [x] Essai réel avec Ollama si disponible (`claude` ↔ `ollama`, réponse streamée, stop).
- [ ] Revue avec toi avant l'interface et les outils.

- [x] **T4 : Mémoire, pastille « distant » (interface)**
  - Acceptance : `send_memory` suit la règle (vrai en local, faux sinon, réglage explicite prioritaire) ; la requête n'embarque pas `memory.md` quand c'est faux ; `agents` émet `remote` ; l'en-tête affiche une pastille « distant » avec info-bulle quand l'agent actif n'est pas local ; chaînes dans `ui_strings()`.
  - Verify : test du corps de requête avec et sans mémoire ; `qmllint overlays/*.qml` ; `test/test-e2e.sh --no-gui` ; vérification visuelle (Quickshell rechargé).
  - Files : `scripts/assistant.py`, `overlays/AssistantOverlay.qml`, `test/test-model-link.py`.
  - Scope : M.

- [x] **T5 : `iris-doctor`**
  - Acceptance : une ligne par agent `openai` : point d'accès joignable (`GET /models`, 3 s), clé présente et en `0600`, modèles déclarés présents quand la réponse les liste ; la clé n'est jamais affichée ; l'outil reste en lecture seule.
  - Verify : exécution contre le faux serveur (ajouter le cas dans le test) ; `shellcheck`/`py_compile`.
  - Files : `scripts/iris-doctor`, `test/test-model-link.py`.
  - Scope : S.

- [ ] **T6 : `install.sh --add-openai`**
  - Acceptance : `--add-openai "nom=base_url,fast=ID,power=ID[,key_file=CHEMIN]"` (répétable) écrit l'entrée dans `config.json` après les mêmes validations que le daemon ; nom ≠ `claude` ; `--dry-run` n'écrit rien ; rien n'est exécuté ni téléchargé ; sauvegarde `.iris-bak` conservée ; entrée existante non écrasée sans accord.
  - Verify : `shellcheck --severity=warning install.sh` ; `test/test-e2e.sh --no-gui` étendu d'un cas ; `./install.sh --dry-run --add-openai …`.
  - Files : `install.sh`, `test/test-e2e.sh`.
  - Scope : S.

- [ ] **T7 : Docs, exemple, CI**
  - Acceptance : `integration/config.example.json` et le commentaire `AGENTS_HELP` documentent `type: "openai"` ; README FR + `docs/README.en.md` (section « Autre modèle ») ; `AGENTS.md` (carte du dépôt, règles) ; `CHANGELOG.md` ; étapes `test-model-link.py` ajoutées à `.github/workflows` (compile + test).
  - Verify : relecture ; la CI complète tourne en local (liste des commandes du workflow).
  - Files : `integration/config.example.json`, `README.md`, `docs/README.en.md`, `AGENTS.md`, `CHANGELOG.md`, `.github/workflows/*.yml`.
  - Scope : M.

### Checkpoint : module terminé
- [ ] Tous les critères de réussite de la spec sont cochés.
- [ ] `READONLY_BASH`, `BILLING_ENV`, commandes interdites : `git diff main -- scripts/assistant.py` ne les touche pas.
- [ ] `ponytail-review` passé sur le diff avant tout commit final / PR.
- [ ] PR `feat/model-link` → `main` ouverte seulement si tu le demandes (description sans attribution).
