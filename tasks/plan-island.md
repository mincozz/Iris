# Plan : island-ui

Spec : `specs/SPEC-island.md` (validée, valeurs par défaut). Tâches dans `tasks/todo-island.md` (suivi markdown). Branche `feat/island-ui`, depuis `main`. Un commit par tâche, **sans mention de l'assistant**. Rien n'est poussé sans ton accord.

## Décisions
- **QML seulement.** Daemon, IPC et contrat hôte ne changent pas. Les textes passent par `overlay.tr(clé, défaut)` ; les clés vont dans `ui_strings()`, c'est la seule ligne Python touchée.
- **Une tranche visible par tâche**, du repos vers l'ouvert : repos → actif → carte ouverte → onglets → chat → accueil → fichiers → finitions. Chaque tâche laisse Iris utilisable et installable.
- **Découpage modéré.** `AssistantOverlay.qml` (1 630 lignes) garde l'état, le daemon et la liste de messages ; on en sort seulement ce qui est neuf : `AssistantTabs.qml`, `AssistantHome.qml`, `AssistantFiles.qml`. La liste de messages est restylée sur place (la sortir risquerait les cartes Autoriser / Refuser).
- **Géométrie.** Fenêtre toujours plein écran en couche `overlay`, `exclusiveZone: 0`, masque d'entrée limité à l'îlot (fermé) ou à tout l'écran (ouvert). L'îlot est à `y: 0` : il recouvre le milieu de ta barre (40 px, milieu libre) sans toucher ses modules gauche et droite.
- **Un progrès `p` (0→1) ouvre la carte ; un progrès `act` (0→1) fait grossir l'îlot actif.** Largeur du repos mesurée avec `TextMetrics`, bornée à 200–420 px.
- **Étapes d'outils de l'Accueil** : tableau `steps` rempli depuis les événements déjà reçus (`toolStatus`, résultats), sans nouvelle commande.
- **Rappels de l'Accueil** : lecture seule de `~/.local/share/qs-assistant/reminders.json` par un `FileView` de Quickshell (pas de commande daemon, donc protocole inchangé). Si le fichier est absent ou illisible, la section est masquée.
- **Noir fixe** (`#000` îlot, noir légèrement teinté pour la carte), accents pris dans `theme`.
- **Taille de la carte** : 640 px de large, 70 % de l'écran au plus.

## Graphe de dépendances
```
T1 repos ── T2 actif ──┐
                       ├── T3 carte ouverte ── T4 onglets ── T5 chat ──┬── T6 accueil
                       │                                              └── T7 fichiers
                                                                           └── T8 finitions ── T9 docs + installateur
```
T6 et T7 sont indépendantes (fichiers différents) ; on les fait dans l'ordre pour éviter les conflits sur l'overlay.

## Risques
| Risque | Impact | Mitigation |
|---|---|---|
| Une erreur QML casse **toute ta barre** au rechargement | Haut | `qmllint` avant chaque installation ; j'installe à chaque point d'arrêt, pas à chaque sauvegarde ; retour arrière : `git switch main && ./install.sh -y` (les `.iris-bak` restent) |
| Masque d'entrée mal calé : l'îlot vole des clics à la barre, ou la carte ouverte laisse des trous | Haut | Masque lié aux rectangles réels ; test à la main : clic sur un module de la barre à gauche et à droite de l'îlot |
| Animation d'ouverture qui saccade ou qui laisse l'îlot et la carte désynchronisés | Moyen | Un seul `p` pilote largeur, hauteur, rayon et opacité (comme `SPEC-buddy`) ; test visuel à 3 instants |
| Focus clavier : `Ctrl+1/2/3` ou `Échap` capturés par le champ de saisie | Moyen | `Shortcut` au niveau de la fenêtre ; test Maj+Entrée / Entrée / Échap |
| Restyle des bulles qui casse les cartes Autoriser / Refuser | Haut | Ne toucher qu'au conteneur extérieur ; test à la main avec une demande qui déclenche une carte, puis Refuser |
| `steps` de l'Accueil incohérent (événements qui arrivent dans le désordre) | Faible | Remis à zéro à chaque nouveau message ; au plus 6 lignes affichées |
| Vérification visuelle intrusive | Moyen | Captures **recadrées** sur l'îlot seulement (`grim -g`), supprimées après lecture |
| Vérifier l'état actif demande un vrai message à Claude | Faible | Un message minuscule au modèle rapide, au point d'arrêt T2 seulement |
| Nouveaux fichiers oubliés par l'installateur | Moyen | T4 ajoute les fichiers à `FILES` (`install.sh`, `iris-doctor`) dès qu'ils existent ; `test-e2e.sh` le vérifie |

## Points d'arrêt (revue avec toi)
- Après **T2** : repos et actif, installés, à regarder chez toi.
- Après **T5** : carte ouverte, onglets et chat.
- Après **T9** : fin du module, revue `ponytail-review`, puis push seulement si tu le demandes.

## Questions ouvertes
Aucune bloquante. Valeurs par défaut retenues : lecture directe de `reminders.json` pour l'Accueil, noir fixe, 640 px.
