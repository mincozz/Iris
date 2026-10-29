# Spec : island-ui (l'îlot Iris, fidèle à Coucou)

Référence visuelle : les captures `docs/media/claude-code.png`, `chat.png` et `upload.png` de <https://github.com/Louis-CFM/coucou>. On reprend l'**ergonomie et la mise en page**, pas le code (Swift) ni la mascotte (Mochi) : Iris garde son pixel art.

## Objectif
Remplacer la pastille de 176×40 et le panneau latéral par **un seul îlot noir collé au bord haut de l'écran**, au centre. Il a trois états : repos, actif (un agent travaille, plus gros) et ouvert (carte à onglets). Toutes les fonctions actuelles d'Iris restent, mais mieux rangées.

Pourquoi : aujourd'hui la pastille est petite, son texte est coupé (« Coucou, je s… »), et le panneau est une colonne pleine hauteur avec des boutons d'en-tête serrés. Succès = on comprend l'état d'Iris d'un coup d'œil, et chaque action courante est à un clic.

## Comportement
1. **Repos** : îlot noir, coins bas arrondis, centré en haut, collé au bord (il recouvre le milieu libre de la barre). Mascotte à gauche, une ligne d'état à droite (humeur, rappel, alerte). **Largeur selon le contenu**, de 200 à 420 px, texte jamais coupé tant qu'il tient ; au-delà, points de suspension. Point de couleur si message non lu.
2. **Actif** (Iris répond, ou une action tourne) : l'îlot **grandit** (≈ 360×64) et montre l'étape en cours (« Lecture de … », « Réflexion… », « Commande… ») avec un indicateur animé. Il redevient discret à la fin, avec l'humeur « content ».
3. **Survol** : l'îlot s'agrandit légèrement. **Clic** : ouverture. **Fichier survolé** : il s'élargit avec « Lâche ici » ; lâché, les fichiers (≤ 5) sont joints et l'onglet Chat s'ouvre.
4. **Ouvert** : l'îlot se déplie en une carte arrondie (≈ 640 px de large, hauteur selon le contenu, 70 % de l'écran au plus), **une seule animation continue**. Rangée d'onglets en haut, comme Coucou :
   - **Accueil** : grande mascotte à gauche, nom, agent et modèle actifs (avec « distant » si besoin), liste des étapes du tour en cours ou du dernier (`Read ✓`, `Edit ⟳`, `Bash`, `Terminé`), puis rappels et alertes en attente.
   - **Chat** : bulles sobres (message de l'utilisateur à droite en pastille, réponse d'Iris à gauche avec une puce « nom de l'agent »), trois points animés pendant l'attente, cartes Autoriser / Refuser inchangées, champ « Continue… » avec **bouton d'envoi rond**. Entrée envoie, Maj+Entrée saute une ligne.
   - **Fichiers (+)** : zone de dépôt, fichiers joints sous forme de pastilles retirables, image collée avec `Ctrl+V`.
   - À droite de la rangée : historique (avec recherche), nouvelle conversation, changement d'agent, mise à jour.
5. **Clavier** : `Échap` ferme, `Ctrl+1/2/3` change d'onglet, le champ de saisie a le focus à l'ouverture sur Chat.
6. **Ergonomie** : cibles cliquables ≥ 32 px, texte courant ≥ 14 px, contraste ≥ 4,5:1, aucune action courante à plus de deux clics, l'îlot ne capte aucun clic hors de lui quand il est fermé.

## Contrat hôte (inchangé)
`shellRoot` : `assistantOpen`, `assistantMood`, `assistantUnread`, `closeAssistant()`, `configDir`, `homeDir` ; `theme` : mêmes champs qu'aujourd'hui. IPC `assistant` (`toggle`, `open`, `close`, `ask`, `prefill`, `reveal`) et protocole du daemon **inchangés** : le redesign est du QML, pas de nouvelle commande.

## Commandes
```
Lint   : qmllint overlays/*.qml
E2E    : test/test-e2e.sh --no-gui
Daemon : for t in test/test-*.py; do python3 -I "$t"; done   # (sauf test-actions et test-update-button, lancés par l'e2e)
Voir   : ./install.sh -y puis grim -g "X,Y WxH" capture.png   # recadrage serré sur l'îlot, jamais l'écran entier
```

## Structure
- `overlays/AssistantOverlay.qml` (1 600 lignes) est découpé par rôle : l'îlot et son animation, la rangée d'onglets, une vue par onglet, la bulle de message. Fichiers nouveaux dans `overlays/` ; `AssistantOverlay` reste le point d'entrée et garde l'état (propriétés, `onEvent`).
- `install.sh` et `scripts/iris-doctor` : listes de fichiers à compléter (`FILES`), sinon l'installation oublie les nouveaux composants.
- `overlays/AssistantAvatar.qml` : taille variable (petit à gauche du repos, grand sur l'Accueil).
- Textes via `overlay.tr(clé, défaut)` ; clés dans `ui_strings()` de `assistant.py`.

## Style de code
Même gabarit que l'existant : propriétés `overlay.theme.*`, un seul progrès d'ouverture `p` (0→1) qui pilote largeur, hauteur, rayon et opacité, `Behavior` pour les petites animations.
```qml
Rectangle {
    width: contentW + 28; height: 36 + (activeH - 36) * overlay.act
    radius: 18; color: "#000"
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
}
```

## Tests
- `qmllint overlays/*.qml` sans avertissement, `test-e2e.sh --no-gui` (installation de tous les fichiers, câblage, doctor), tous les tests du daemon inchangés.
- Vérification visuelle **par capture recadrée** à chaque état : repos, actif, survol de fichier, Accueil, Chat avec carte Autoriser, Fichiers, historique. Liste de contrôle dans `tasks/todo-island.md`, cochée avec toi.
- Le daemon ne change pas : aucun nouveau test Python, sauf si une clé de texte est ajoutée (test de couverture `ui_strings`).

## Limites
- **Toujours** : garder le contrat hôte et les cartes Autoriser / Refuser ; textes via `tr()` ; un commit par étape visible ; relancer l'e2e.
- **Demander d'abord** : ajouter une dépendance ou une police, changer le protocole du daemon, déplacer l'îlot hors du centre haut.
- **Jamais** : retirer le bouton Stop, masquer une carte d'autorisation, capter des clics hors de l'îlot à l'état fermé, prendre une capture de l'écran entier.

## Critères de réussite
- Repos : la phrase d'état « Coucou, je suis là » s'affiche en entier ; l'îlot ne gêne pas la barre (ses modules gauche et droite restent cliquables).
- Actif : l'étape en cours est lisible sans ouvrir.
- Déposer un fichier sur l'îlot fermé l'attache et ouvre le Chat ; il apparaît en pastille retirable ; Iris le lit au message suivant.
- Accueil, Chat et Fichiers existent, `Ctrl+1/2/3` les change, `Échap` ferme.
- Envoyer, arrêter, changer d'agent, rechercher dans l'historique, autoriser / refuser : tout marche comme avant.
- `qmllint` propre, e2e vert, aucune erreur QML dans `qs log` après rechargement.

## Hypothèses (à corriger maintenant)
1. L'îlot **recouvre le milieu libre de ta barre** (modules à gauche et à droite) au lieu de s'asseoir dessous. Je n'ai pas lu `bar/Bar.qml` : la hauteur réelle de la barre reste à mesurer.
2. Le noir est **fixe** (`#000` pour l'îlot, un noir légèrement teinté pour la carte), comme Coucou, et non dérivé de `theme.bg`. Les accents (puce de l'agent, étapes) viennent de `theme`.
3. Pas de coins concaves « oreilles » autour de l'îlot (effet d'encoche) : coûteux en QML pour peu de gain.
4. Hors périmètre ici : visionneuse de diff, sessions d'agents externes, son (`pill-active` et `hook-bridge` s'y brancheront), stats (`mascot-stats`).
5. Les onglets Accueil / Chat / Fichiers suffisent ; pas d'onglet Réglages.

## Questions ouvertes
1. **Noir fixe ou couleur de ton thème** pour l'îlot ? (hypothèse 2 : noir fixe)
2. **Recouvrir la barre** (hypothèse 1) ou rester sous la barre ?
3. **Onglet Accueil** : tu veux y voir les étapes d'outils et les rappels, ou seulement la mascotte et l'état ?
4. **Taille** : carte ouverte de 640 px de large, ça te va, ou plus grande ?
