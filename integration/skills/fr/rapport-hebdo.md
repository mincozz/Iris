---
description: Résume mon activité git de la semaine dans mes projets (« rapport de la semaine », « qu'est-ce que j'ai fait cette semaine »)
---
1. Trouve mes dépôts : `ls -d ~/*/.git ~/*/*/.git` (si mes projets sont ailleurs, regarde ta mémoire ou demande-moi où).
2. Pour chaque dépôt, liste mes commits des 7 derniers jours : `git -C <dépôt> log --since="7 days ago" --oneline`. Ignore les dépôts sans commit récent.
3. Réponds par une courte liste par projet (2 à 4 puces, ce qui a changé et pourquoi), puis une phrase de synthèse. Pas de tableau.
