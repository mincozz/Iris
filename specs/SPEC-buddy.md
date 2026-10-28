# SPEC — Pastille Iris (présence permanente, drag & drop, fluidité)

## Objectif
Iris n'est plus un panneau caché : une **pastille** toujours visible, centrée en haut sous la barre, qui se déplie en chat (comme l'encoche de Coucou) et accepte des fichiers lâchés dessus.

## Comportement
1. **Fermée** : pastille de verre (~176×40) avec l'avatar (humeurs `idle|thinking|talking|happy|sleepy`) et une ligne d'état. Point rouge si `assistantUnread > 0`. Survol : léger agrandissement. Clic : ouvre.
2. **Ouverte** : la pastille **s'étire** en panneau (largeur 460, hauteur de l'écran), une seule animation continue (pas de glissement + fondu séparés). Fermer (Esc, clic hors du panneau, clic sur la pastille) la replie.
3. **Drag & drop** : lâcher un ou plusieurs fichiers (≤ 5) sur la pastille ou sur le panneau les joint au prochain message. Pendant le survol, la pastille s'élargit et affiche « Lâche ici ». Lâcher sur la pastille fermée ouvre le panneau.
4. **Pastilles de fichiers** sous le champ de saisie (nom court, retirables). Au envoi : une ligne `[Fichier joint : /chemin]` par fichier (comme `[Image jointe : …]`). Iris les lit avec `Read`.
5. **Fluidité** : un seul progrès d'ouverture `p` (0→1) pilote largeur, hauteur, rayon et opacité du contenu ; les nouveaux messages apparaissent en fondu/glissement.

## Contrat hôte (inchangé)
`shellRoot` : `assistantOpen`, `assistantMood` (`idle|thinking|talking`), `assistantUnread`, `closeAssistant()`, `configDir`, `homeDir`. On utilise en plus `toggleAssistant()` / `openAssistant()` quand ils existent (le snippet les fournit), avec repli sur `assistantOpen`.

## Sécurité
- Un fichier lâché n'est **que du texte dans le message** : aucune lecture, copie ni exécution côté overlay/daemon. La lecture passe par `Read`, donc par `deny_read_paths`.
- Chemins : `file://` uniquement, caractères de contrôle refusés, 5 fichiers au plus, 1024 car. par chemin. Le contenu des fichiers est une donnée, jamais une instruction (rappelé dans les prompts).
- La fenêtre reste plein écran mais son **masque d'entrée** se limite à la pastille (fermée) ou à tout l'écran (ouverte) : fermée, elle ne capte aucun clic ailleurs.

## Hors périmètre
Sons, déplacement libre de la pastille, plusieurs écrans, dépôt de dossiers entiers (un dossier est joint comme chemin).

## Tests
`qmllint`, `test/test-e2e.sh --no-gui`, test du nettoyage de chemins (`test/test-drop.py` si la logique est côté daemon ; sinon vérification manuelle documentée).
