# Contribuer à Iris / Contributing

Merci de ton intérêt ! / Thanks for your interest! (English summary at the bottom.)

## Avant de commencer

- Ouvre d'abord une issue pour une grosse fonctionnalité, qu'on se mette d'accord sur le principe.
- Une faille de sécurité ne s'ouvre **pas** en issue publique : voir [SECURITY.md](SECURITY.md).

## Mettre en place

```bash
git clone git@github.com:mincozz/IRIS.git && cd IRIS
test/test-e2e.sh --no-gui      # installe dans un dossier jetable (/tmp), vérifie, désinstalle
```

Ce test ne touche ni ton shell, ni ton `~/.local/share/qs-assistant`, ni ton compte Claude. Avec `--with-claude`, il utilise **ton** compte pour un message minuscule ; sans `--no-gui`, il ouvre une instance Quickshell de test.

La CI (`.github/workflows/ci.yml`) lance ShellCheck (`--severity=warning`), la compilation Python, ce test et Gitleaks.

## Conventions

- **Textes visibles** : tout nouveau texte passe par `pick("français", "english")` (Python, `scripts/i18n.py`) ou `overlay.tr("clé", "défaut")` côté QML, avec la clé ajoutée dans `ui_strings()` de `scripts/assistant.py`.
- **Sécurité** : ne rends jamais « auto-approuvée » une commande qui peut écrire ou exécuter selon ses arguments (voir `READONLY_BASH`). Toute nouvelle action de bouton valide ses arguments côté daemon (`Daemon._run_action`) et a un test dans `test/test-actions.py`.
- **Aucune donnée perso** dans le repo : ni chemins, ni adresses, ni secrets. L'état de l'utilisateur vit dans `~/.local/share/qs-assistant/`.
- **Tests** : une fonctionnalité ou un correctif ajoute sa vérification dans `test/test-e2e.sh` (ou un script `test/test-*.py` appelé par lui).
- **Commits** : un sujet clair à l'impératif (`Add …`, `Fix …`), un commit par sujet.
- **Shell** : `install.sh` et les scripts doivent rester passer ShellCheck au niveau `warning`.

## Pull request

1. `test/test-e2e.sh --no-gui` doit passer (la CI le refait).
2. Décris ce qui change et pourquoi, et comment tu l'as testé (ce qui est visuel et que la CI ne peut pas voir, surtout).
3. Mets à jour `README.md` / `README.en.md` / `AGENTS.md` si le comportement visible change.

Les contributions sont acceptées sous la licence du projet ([MIT](LICENSE)).

## English summary

Open an issue before big features. Report vulnerabilities privately (see `SECURITY.md`). Run `test/test-e2e.sh --no-gui` before a pull request (it works in a throwaway folder and never touches your shell, your data or your Claude account unless you pass `--with-claude`). Route user-visible strings through `pick(fr, en)` / `overlay.tr(key, default)`, never auto-approve commands that can write or execute depending on their arguments, keep personal data out of the repo, and add a test for what you change. ShellCheck (`--severity=warning`) must pass.
