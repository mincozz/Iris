# Tâches : island-ui

Plan : `tasks/plan-island.md`. Spec : `specs/SPEC-island.md`.
Contrôles à chaque tâche : `qmllint overlays/*.qml` sans avertissement ; `test/test-e2e.sh --no-gui` vert ; après installation, `qs log` sans erreur d'`Assistant*` ; capture **recadrée** avec `grim -g "X,Y WxH"`, jamais l'écran entier.
Commits sans mention de l'assistant.

- [x] **T1 : Îlot au repos**
  - Acceptance : îlot noir à `y: 0`, centré, coins bas arrondis ; mascotte à gauche, ligne d'état à droite ; largeur 200–420 px selon le texte, « Coucou, je suis là » affiché en entier ; point si non lu ; léger agrandissement au survol ; « Lâche ici » au survol d'un fichier ; le masque d'entrée ne couvre que l'îlot.
  - Verify : capture recadrée ; clic sur les modules de la barre à gauche et à droite : ils répondent ; clic sur l'îlot : ouvre toujours le panneau actuel.
  - Files : `overlays/AssistantOverlay.qml`, `scripts/assistant.py` (clé de texte éventuelle).
  - Scope : M.

- [x] **T2 : Îlot actif**
  - Acceptance : quand Iris répond, l'îlot grossit (≈ 360×64) avec l'étape en cours (« Réflexion… », « Lecture de … ») et un indicateur animé ; à la fin il se replie avec l'humeur « content ». L'état est piloté par `busy` et `toolStatus`.
  - Verify : un message minuscule au modèle rapide (`qs ipc call assistant ask "dis ok"`) et trois captures recadrées (repos, actif, retour) ; aucune erreur dans `qs log`.
  - Files : `overlays/AssistantOverlay.qml`.
  - Scope : S.

### Point d'arrêt : repos et actif
- [ ] Installé chez toi et validé visuellement. Revue avant d'attaquer la carte.

- [x] **T3 : Carte ouverte (géométrie et animation)**
  - Acceptance : l'îlot se déplie en une carte noire de 640 px (hauteur selon le contenu, 70 % de l'écran au plus) par un seul progrès `p` ; le contenu actuel (en-tête, historique, messages, saisie) y est placé tel quel ; refermer (clic dehors, `Échap`, clic sur l'îlot) la replie ; plus de panneau latéral pleine hauteur.
  - Verify : captures à `p` ≈ 0, 0,5 et 1 ; envoyer un message ouvert ; clic dehors ferme ; barre toujours cliquable fermé.
  - Files : `overlays/AssistantOverlay.qml`.
  - Scope : M.

- [x] **T4 : Onglets Accueil / Chat** (l'onglet Fichiers, d'abord prévu, a été supprimé le 2026-10-29)
  - Acceptance : `AssistantTabs.qml` (rangée d'onglets, gauche) ; à droite : historique, nouvelle conversation, agent, mise à jour (≥ 32 px chacun) ; `Ctrl+1/2` change d'onglet, `Échap` ferme, focus sur la saisie à l'ouverture du Chat ; onglets Accueil et Fichiers provisoires (vides) ; `AssistantTabs.qml` ajouté à `FILES` dans `install.sh` et `iris-doctor`.
  - Verify : captures des deux onglets ; raccourcis clavier à la main ; `test-e2e.sh --no-gui` (fichier installé et listé par le doctor).
  - Files : `overlays/AssistantTabs.qml`, `overlays/AssistantOverlay.qml`, `install.sh`, `scripts/iris-doctor`.
  - Scope : M.

- [ ] **T5 : Chat restylé**
  - Acceptance : message de l'utilisateur en pastille à droite ; réponse d'Iris à gauche avec une puce « nom de l'agent » ; trois points animés pendant l'attente ; champ « Continue… » avec bouton d'envoi rond ; Entrée envoie, Maj+Entrée saute une ligne ; **cartes Autoriser / Refuser, bouton Stop, copie et liens inchangés**.
  - Verify : captures ; une demande qui déclenche une carte (puis Refuser) ; Stop pendant une réponse ; texte multi-lignes.
  - Files : `overlays/AssistantOverlay.qml`, `scripts/assistant.py` (clés de texte).
  - Scope : M.

### Point d'arrêt : carte, onglets, chat
- [ ] Installé chez toi et validé. Revue avant l'Accueil.

- [ ] **T6 : Onglet Accueil**
  - Acceptance : grande mascotte à gauche (taille variable d'`AssistantAvatar`) ; nom d'Iris, agent et modèle actifs, étiquette « distant » si besoin ; liste des étapes du tour en cours ou du dernier (`Read ✓`, `Edit ⟳`, `Bash`, `Terminé`, 6 lignes au plus) ; alertes non lues ; prochain rappel lu dans `reminders.json` (section masquée si absent).
  - Verify : captures avant / pendant / après un message ; rappel créé avec `iris-remind add` dans un `HOME` d'essai (sans toucher ton `reminders.json`) ; fichier absent : pas d'erreur.
  - Files : `overlays/AssistantHome.qml`, `overlays/AssistantAvatar.qml`, `overlays/AssistantOverlay.qml`, `install.sh`, `scripts/iris-doctor`.
  - Scope : M.

- [x] **T7 : Fichiers dans le Chat : trombone, dépôt, Ctrl+V** (remplace l'onglet Fichiers)
  - Acceptance : un trombone à gauche de la saisie ouvre le sélecteur de fichiers du bureau (`scripts/iris-pick`) ; le panneau se referme pendant le choix puis revient avec les fichiers en pastilles retirables (≤ 5) ; le dépôt sur l'îlot ou la carte et `Ctrl+V` fonctionnent toujours ; mêmes contrôles de chemin pour les trois (absolu, 1 024 caractères au plus, pas de caractère de contrôle, pas de doublon).
  - Verify : `test/test-pick.py` (faux kdialog / zenity : sortie, annulation, absence) ; capture recadrée du trombone ; à la main : trombone → choisir 2 fichiers, annuler, dépôt depuis ton gestionnaire de fichiers.
  - Files : `scripts/iris-pick`, `overlays/AssistantOverlay.qml`, `install.sh`, `scripts/iris-doctor`, `test/test-pick.py`.
  - Scope : M.

- [ ] **T8 : Finitions d'ergonomie**
  - Acceptance : cibles ≥ 32 px, texte courant ≥ 14 px, contraste ≥ 4,5:1 (mesuré sur les couleurs), historique et recherche dans la carte, animation fluide à l'ouverture et à la fermeture répétées, aucune erreur dans `qs log` après 20 ouvertures / fermetures.
  - Verify : script de contraste sur les paires de couleurs ; 20 bascules via `qs ipc call assistant toggle` ; relecture de la liste de la spec.
  - Files : `overlays/*.qml`.
  - Scope : S.

- [ ] **T9 : Docs, installateur, CI**
  - Acceptance : README FR / EN (section d'aperçu, raccourcis `Ctrl+1/2`), `CHANGELOG.md`, `AGENTS.md` (carte du dépôt) ; `FILES` à jour partout ; `SPEC-buddy.md` marquée remplacée par `SPEC-island.md`.
  - Verify : `test-e2e.sh --no-gui`, `shellcheck`, CI complète en local.
  - Files : `README.md`, `docs/README.en.md`, `CHANGELOG.md`, `AGENTS.md`, `specs/SPEC-buddy.md`.
  - Scope : S.

### Point d'arrêt : fin du module
- [ ] Critères de réussite de la spec tous cochés.
- [ ] `ponytail-review` passé sur le diff.
- [ ] Push sur `main` seulement sur ta demande.
