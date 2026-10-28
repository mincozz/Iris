# Capability Map : recherche, rappels, images

Trois fonctionnalités indépendantes (données, consommateurs et tests différents). Chacune aura sa propre spec `SPEC-<id>.md` après validation de cette carte.

| Module id | Responsabilité | Dépend de |
|---|---|---|
| `history-search` | Champ de recherche plein texte dans la vue Historique ; le daemon parcourt `history/*.json` et renvoie les conversations qui correspondent, avec un extrait. | — |
| `reminders` | « Rappelle-moi dans 20 min / demain 9h » : stockage `reminders.json`, déclenchement par `iris-watch`, notification + message dans le panneau. | — |
| `image-input` | Joindre une image (coller `Ctrl+V`, glisser-déposer, `iris-ask --screenshot`) ; le fichier est copié dans `~/.local/share/qs-assistant/attachments/` et Claude le lit avec `Read`. | — |

Ordre de construction : `history-search` → `reminders` → `image-input`
(du plus petit et sans risque au plus sensible ; aucune dépendance technique, l'ordre sert à limiter les conflits sur `assistant.py` / `AssistantOverlay.qml` et à commiter une capacité à la fois).

## Hypothèses (à corriger maintenant)
1. **history-search** : recherche insensible à la casse et aux accents, sur le titre et le texte des messages (pas les cartes d'outils). Un scan des fichiers JSON suffit (pas d'index) tant que l'historique reste modeste.
2. **reminders** : les rappels sont créés par Iris (langage naturel), pas par un formulaire. Pour que ça reste dans la règle « tout ce qui modifie passe par Autoriser / Refuser », un petit script `scripts/iris-remind` (`add`, `list`, `cancel`, dates validées) est appelé via Bash et affiche sa carte d'accord. Le texte du rappel est de la donnée, jamais une instruction. Rappel unique d'abord, pas de récurrence.
3. **image-input** : seul l'agent `claude -p` voit les images (les agents `CommandAgent` génériques les ignorent, avec un message clair). Formats png/jpg/webp, taille plafonnée, fichiers stockés en `0700` sous `DATA_DIR` et purgés après N jours. Le collage d'image passe par `wl-paste --type image/*` (Quickshell ne lit pas le presse-papiers image nativement).
4. Tout texte visible passe par `pick(fr, en)` / `overlay.tr(...)`, chaque capacité ajoute ses tests dans `test/`, et README FR/EN + `CHANGELOG.md` sont mis à jour.
5. Aucun changement à `READONLY_BASH`, `BILLING_ENV` ni aux commandes interdites.

## Questions ouvertes
- **Rappels** : voulez-vous aussi une récurrence (« tous les lundis ») dès la v1, ou rappel unique seulement ?
- **Images** : le collage `Ctrl+V` et le glisser-déposer sont-ils tous deux nécessaires, ou seulement `iris-ask --screenshot` + collage ?
- **Images** : durée de conservation des pièces jointes (proposition : 7 jours) ?
- **Recherche** : filtrer l'historique en direct à chaque frappe, ou à la touche Entrée ?
