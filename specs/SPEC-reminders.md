# Spec : reminders

## Objectif
« Rappelle-moi dans 20 min d'appeler X » : Iris enregistre un rappel **unique** ; à l'heure dite, `iris-watch` envoie une alerte (notification + message dans le panneau).

## Comportement
- Création par Iris via `scripts/iris-remind add <quand> "<texte>"` ; l'appel passe par la carte **Autoriser / Refuser** (non ajouté à `READONLY_BASH`). Le texte montré est la commande entière.
- `<quand>` : `+20m`, `+2h`, `+3d` ou `YYYY-MM-DD HH:MM` (heure locale). Iris convertit le langage naturel avant l'appel.
- Annulation : `iris-remind cancel <id>`. Liste : Iris lit `reminders.json` avec `Read` (déjà autorisé), pas de sous-commande `list`.
- Échéance : `iris-watch` (boucle de 30 s) émet une alerte `kind="reminder"` puis supprime le rappel. Rappel manqué (PC éteint) : envoyé au prochain démarrage, avec l'heure d'origine.

## Commandes
- Tests : `python3 -I test/test-remind.py`. CI : ajouter `iris-remind` et le test à `py_compile` + étape de test.

## Structure
- `scripts/iris-remind` (Python) : écrit `~/.local/share/qs-assistant/reminders.json` (fichier à part, pas `watch.json`).
- `scripts/iris-watch.py` : `check_reminders` dans `CHECKS` (toutes les 30 s).
- `scripts/assistant-prompt.md` / `.en.md` : usage de `iris-remind`. `install.sh` : copie du script. README FR/EN, CHANGELOG.

## Style
Python stdlib, `pick(fr, en)` via `i18n.py`, écriture atomique (`.tmp` + `os.replace`) comme `watch.save`.

## Tests
Date passée refusée, > 1 an refusée, texte vide ou > 200 car. refusé, plafond de 50 rappels, échéance déclenche exactement une alerte puis disparaît, rappel manqué déclenché au démarrage.

## Limites
- Toujours : valider l'heure et la taille côté script, échapper le texte (`esc()`) dans l'alerte, le traiter comme donnée.
- Demander d'abord : tout bouton d'action sur l'alerte (« Reporter »), récurrence (hors périmètre).
- Jamais : exécuter le texte du rappel, toucher à `READONLY_BASH`, écrire hors de `DATA_DIR`.
- `shortcut:` écriture concurrente `iris-remind` / `iris-watch` sans verrou (fenêtre de quelques ms) ; ajouter `fcntl.flock` si ça se produit.

## Critères de réussite
- « Rappelle-moi dans 2 min de tester » → carte → au bout de 2 min une alerte « Rappel : tester » apparaît, une seule fois.
- Redémarrer iris-watch ne duplique ni ne perd un rappel.
