# Tâches

Vérification commune : `python3 -I -m py_compile <fichiers touchés>` et `test/test-e2e.sh --no-gui` (la CI doit rester verte).

## Phase 1 : history-search
- [x] **T1 Daemon : commande `search`** (S)
  - Critères : `{cmd:"search", q}` renvoie `history` avec `snippet` ; sans accents/casse ; 30 résultats ; q vide = liste ; q tronquée à 100.
  - Vérif : `python3 -I test/test-search.py`.
  - Fichiers : `scripts/assistant.py`, `test/test-search.py`, `.github/workflows/ci.yml`.
- [x] **T2 Champ de recherche dans l'historique + docs** (S)
  - Critères : champ en haut de la vue, filtre à chaque lettre, extrait affiché, placeholder via `tr()`, README FR/EN + CHANGELOG.
  - Vérif : `test/test-e2e.sh` ; manuel : taper « reunion » trouve « Réunion ».
  - Dépend de : T1. Fichiers : `overlays/AssistantOverlay.qml`, `scripts/assistant.py` (`ui_strings`), `README.md`, `docs/README.en.md`, `docs/CHANGELOG.md`.
- [x] **Checkpoint 1** : CI verte, recherche fluide avec ~200 conversations, relecture (`ponytail-review`) puis commit.

## Phase 2 : reminders
- [x] **T3 `iris-remind` (add / cancel) + install** (M)
  - Critères : formats `+20m|h|d` et `YYYY-MM-DD HH:MM` ; refus passé, > 1 an, texte vide ou > 200, > 50 rappels ; écriture atomique `0600`.
  - Vérif : `python3 -I test/test-remind.py`.
  - Fichiers : `scripts/iris-remind`, `test/test-remind.py`, `install.sh`, `.github/workflows/ci.yml`.
- [x] **T4 Déclenchement par `iris-watch` + prompts + docs** (M)
  - Critères : `check_reminders` (30 s) émet une alerte `reminder` une seule fois puis supprime ; rappel manqué envoyé au démarrage ; texte échappé ; prompts FR/EN expliquent l'usage ; README FR/EN + CHANGELOG.
  - Vérif : `test-remind.py` (cas échéance) ; manuel : « rappelle-moi dans 2 min » → carte → alerte.
  - Dépend de : T3. Fichiers : `scripts/iris-watch.py`, `scripts/assistant-prompt.md`, `scripts/assistant-prompt.en.md`, `README.md`, `docs/CHANGELOG.md`.
- [x] **Checkpoint 2** : CI verte, rappel de bout en bout, revue de sécurité (texte = donnée, `READONLY_BASH` inchangé), commit.

## Phase 3 : image-input
- [x] **T5 Spike : `Read` lit un PNG hors du cwd** (XS)
  - Critères : `claude -p` avec `Read` décrit un PNG de `attachments/` ; sinon on adapte la spec avant de continuer.
  - Vérif : manuel.
- [x] **T6 Daemon : `paste_image`, purge 7 jours** (M)
  - Critères : `wl-paste --type image/png` → fichier `0600` dans dossier `0700` ; signature PNG, ≤ 10 Mo ; événement `image` ; pas d'image = silence ; purge au démarrage et à chaque collage ; `CommandAgent` refuse avec message.
  - Vérif : `python3 -I test/test-image.py` (faux `wl-paste`).
  - Dépend de : T5. Fichiers : `scripts/assistant.py`, `test/test-image.py`, `.github/workflows/ci.yml`.
- [x] **T7 Overlay : Ctrl+V, pastille, envoi + docs** (M)
  - Critères : Ctrl+V déclenche `paste_image` sans casser le collage texte ; pastille « Image jointe » retirable ; message `[Image jointe : chemin]` ; prompts FR/EN ; README FR/EN + CHANGELOG.
  - Vérif : `test-e2e.sh` ; manuel : capture → Ctrl+V → question → Iris décrit l'image.
  - Dépend de : T6. Fichiers : `overlays/AssistantOverlay.qml`, `scripts/assistant.py` (`ui_strings`), prompts FR/EN, `README.md`, `docs/CHANGELOG.md`.
- [x] **Checkpoint 3** : CI verte, aucun fichier > 7 jours après collage, `ponytail-review`, commit, puis `scripts/iris-update` sur votre PC.
