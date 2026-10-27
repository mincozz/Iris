# Plan : recherche, rappels, images

Specs : `specs/SPEC-*.md`. Tâches suivies dans `tasks/todo.md`. Un commit par tâche, sur la branche `feat/search-reminders-images` (les modifications non commitées actuelles restent à part).

## Décisions
- Une capacité à la fois, du plus petit au plus sensible : recherche → rappels → images. Chaque tranche est verticale (daemon + QML + tests + docs) et laisse `main` installable.
- Aucune nouvelle dépendance. Les tests suivent le style de `test/test-actions.py` (daemon réel, `HOME` jetable) et sont ajoutés à la CI.
- `install.sh` : `scripts/iris-remind` rejoint `FILES` et la liste des fichiers en 755.

## Risques
| Risque | Impact | Mitigation |
|---|---|---|
| `Read` ne lit pas un PNG hors du dossier courant | Haut (images) | Vérifier en tout premier dans la tâche 6, avant le QML |
| Ctrl+V : le collage texte par défaut casse | Moyen | Ne pas marquer l'événement `accepted` ; test manuel texte seul |
| Conflits entre tranches sur `assistant.py` / QML / `ui_strings()` | Faible | Tâches séquentielles, commit par tâche |
| Écriture concurrente `reminders.json` | Faible | Écriture atomique ; limite notée (`shortcut:`) |
| L'état non commité actuel se mélange | Moyen | Branche dédiée, `git add` ciblé |

## Questions ouvertes
Aucune.
