# SPEC — Compagnon Iris (mascotte qui se balade sur le bureau)

## Objectif
Iris peut quitter la pastille et vivre sur le bureau : elle marche, s'assoit, dort, te suit des yeux, réagit aux alertes et aux rappels, et se laisse caresser ou porter. Un mode **à activer** : désactivé par défaut.

## Comportement
1. **Activation** : `qs ipc call assistant companion on|off|toggle` (+ réglage `companion: true|false` dans `settings`). Désactivé : aucune fenêtre, aucun processus de plus.
2. **Terrain** : le sol (bas de l'écran, au-dessus de la barre éventuelle) **et** le bord haut des fenêtres visibles du workspace actif (rectangles lus avec `hyprctl clients -j`, rafraîchis toutes les 2 s et sur changement de workspace). Elle marche, saute d'un support à l'autre et tombe si la fenêtre sous elle disparaît ou bouge.
3. **États** : `idle → wander → sit → sleep`, plus `walk` (sprite retourné), `jump`, `fall`, `held`, `wave`, `curious`. Un seul état à la fois, transitions tirées au sort avec des durées bornées. `sleep` après 5 min d'inactivité (comme `sleepy` aujourd'hui).
4. **Curseur** : `hyprctl cursorpos` à 10 Hz **seulement** quand elle est en `curious` ou `held` (pas de polling sinon). `curious` : elle tourne les yeux vers le curseur ; s'il reste près d'elle, elle vient s'asseoir à côté.
5. **Interactions** : clic = caresse (`happy` + cœur) ; drag = elle est portée (`held`) puis tombe jusqu'au support le plus proche ; double-clic = ouvre le chat. Le reste de l'écran reste cliquable.
6. **Réactions au daemon** (sans appel au modèle) : réponse terminée → saut `happy` ; Iris réfléchit → elle s'assoit, étincelles ; alerte ou rappel → elle accourt près du curseur et affiche une bulle (clic = ouvre le panneau) ; batterie faible → elle bâille / se plaint.
7. **Bulles** : texte court, ≤ 80 car., 6 s, une à la fois, jamais en plein `sleep`. Deux sources :
   - **locale** : phrases FR/EN scriptées (`pick(fr, en)`), aucun quota ;
   - **LLM, rare** : au plus 1 commentaire / 30 min, uniquement si l'utilisateur l'a activé (`companion_chatter: "llm"`), prompt court fixe sans contenu d'écran ni de fichier ; sinon `"local"` (défaut).
8. **Lien avec la pastille** : indépendante. La pastille garde son avatar ; chat ouvert, la mascotte reste dehors mais s'assoit et se tait.

## Contrat hôte
Réutilise `shellRoot.assistantMood`, `assistantUnread`, `openAssistant()`. Nouveau : un `IpcHandler` `companion` (ou une fonction sur `assistant`) et un bloc dans `integration/shell.qml.snippet`. Le daemon publie ses événements (`reply_done`, `alert`, `reminder`) dans un fichier d'état léger déjà lu par l'overlay ; pas de nouveau socket.

## Fichiers prévus
- `overlays/IrisCompanion.qml` : fenêtre layer-shell `overlay`, `exclusiveZone: 0`, masque d'entrée = sprite (+ bulle), machine à états, physique 2D minimale.
- `overlays/AssistantAvatar.qml` : humeurs ajoutées `walk`, `held`, `curious`, sans casser les anciennes (toute valeur inconnue reste `idle`).
- `scripts/companion_geo.py` (ou appel direct `hyprctl`) : rectangles de supports normalisés pour l'écran de la mascotte.
- Phrases dans `scripts/i18n.py`.

## Sécurité et vie privée
- `hyprctl clients` ne sert qu'à lire des **rectangles** ; titres et classes de fenêtres sont jetés tout de suite et jamais envoyés au modèle ni écrits sur disque.
- Commentaire LLM : opt-in explicite, prompt fixe, donnée jamais traitée comme instruction.
- Aucune capture d'écran, aucun clavier global.

## Hors périmètre
Plusieurs écrans (premier écran seulement, `bar-monitors.txt` pour le choix), sons, autres mascottes/skins, mini-jeux, mémoire propre à la mascotte.

## Tests
`qmllint`, `test/test-e2e.sh --no-gui`, test unitaire des supports (`test/test-companion.py` : rectangles → supports, chute, bornes d'écran), vérification manuelle documentée des interactions.

## Risques
Wayland ne donne pas la position du curseur à une fenêtre sans focus : on passe par `hyprctl cursorpos`. Vérifier le coût CPU de l'animation à 60 fps et de la fenêtre plein écran transparente ; repli : fenêtre réduite au rectangle du sprite qui suit la mascotte.
