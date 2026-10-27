# Spec : history-search

## Objectif
Retrouver une ancienne conversation en tapant quelques lettres dans la vue Historique. Le filtre se met à jour à **chaque lettre**.

## Comportement
- Champ de recherche en haut de la liste Historique (focus à l'ouverture de la vue).
- Insensible à la casse et aux accents ; cherche dans le titre et dans le texte des messages `user`/`assistant`/`nudge`.
- Résultats triés par date, 30 au plus, avec un extrait (~80 car.) autour de la première occurrence.
- Champ vide = liste actuelle (inchangée).

## Commandes
- Tests : `python3 -I test/test-search.py` (à ajouter à la CI avec `py_compile`).

## Structure
- `scripts/assistant.py` : commande `{cmd:"search", q}` → `emit("history", v=[{id,title,updated,snippet}])` (même événement que `list`, `snippet` facultatif).
- `overlays/AssistantOverlay.qml` : `TextInput` dans la vue historique, `onTextChanged` → `cmd({cmd:"search", q})`.
- `ui_strings()` : clé `search_placeholder`. `test/test-search.py`, README FR/EN, CHANGELOG.

## Style
`pick(fr, en)` pour tout texte ; même gabarit visuel que le champ de saisie (cardFill / cardStroke).

## Tests
Daemon lancé avec un `HOME` jetable contenant 3 conversations : requête avec accent/majuscule trouve, requête absente renvoie `[]`, requête vide = liste complète, id non valide ignoré.

## Limites
- Toujours : ne lire que `HIST_DIR`, requête tronquée à 100 car., extrait traité comme donnée (affiché en texte brut).
- Jamais : index ou base de données, nouvelle dépendance.
- `shortcut:` scan complet des fichiers à chaque lettre ; indexer au-delà de ~500 conversations.

## Critères de réussite
- Taper « réunion » trouve une conversation contenant « Reunion ».
- Effacer le champ réaffiche tout l'historique.
- La liste reste fluide avec 200 conversations (scan < 100 ms).
