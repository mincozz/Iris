# Contribuer à Iris / Contributing

Merci de l'intérêt que vous portez au projet. English summary at the bottom.

## Avant de commencer

- Ouvrez d'abord une issue pour une grosse fonctionnalité, afin de s'accorder sur le principe. Pour une fonctionnalité non triviale, le dépôt suit : une spécification dans `specs/`, un plan et des tâches dans `tasks/`, puis le code, avec ses tests.
- Une faille de sécurité ne s'ouvre **pas** en issue publique : voir [SECURITY.md](SECURITY.md).

## Mise en place

```bash
git clone https://github.com/mincozz/Iris.git && cd Iris
test/test-e2e.sh --no-gui      # installe dans un dossier jetable (/tmp), vérifie, désinstalle
```

Ce test ne touche ni votre shell, ni votre `~/.local/share/qs-assistant`, ni votre compte Claude. Avec `--with-claude`, il utilise **votre** compte pour un message minuscule ; sans `--no-gui`, il ouvre une instance Quickshell de test.

La CI (`.github/workflows/ci.yml`) lance ShellCheck (`--severity=warning`), la compilation Python, les tests du daemon (`python3 -I test/test-agent.py`, `test-agent-switch.py`, `test-security.py`, `test-search.py`, `test-remind.py`, `test-image.py`, `test-model-link.py`, `test-usage.py`, `test-pick.py`, tous sans compte Claude), ce test et Gitleaks.

## Conventions

- **Textes visibles** : tout nouveau texte passe par `pick("français", "english")` (Python, `scripts/i18n.py`) ou `overlay.tr("clé", "défaut")` côté QML, avec la clé ajoutée dans `ui_strings()` de `scripts/assistant.py`.
- **Sécurité** : ne rendez jamais « auto-approuvée » une commande qui peut écrire ou exécuter selon ses arguments (voir `READONLY_BASH`). Toute nouvelle action de bouton valide ses arguments côté daemon (`Daemon._run_action`) et a un test dans `test/test-actions.py`.
- **Aucune donnée personnelle** dans le dépôt : ni chemins, ni adresses, ni secrets. L'état de l'utilisateur vit dans `~/.local/share/qs-assistant/`.
- **Tests** : une fonctionnalité ou un correctif ajoute sa vérification dans `test/test-e2e.sh` (ou dans un script `test/test-*.py`, lancé par la CI). Un test de daemon utilise un `HOME` jetable et de faux programmes (`wl-paste`, `ollama`, agents en `sh`) : jamais votre compte.
- **Interface** : style « liquid glass » sobre : jetons de `AssistantOverlay.qml` (`cardFill`, `cardStroke`, `glassStroke`…), une seule teinte d'accent, pas d'effet gratuit.
- **Commits** : un sujet clair à l'impératif (`Add …`, `Fix …`), un commit par sujet.
- **Shell** : `install.sh` et les scripts doivent continuer à passer ShellCheck au niveau `warning`.

## Pull request

1. `test/test-e2e.sh --no-gui` doit passer (la CI le refait).
2. Décrivez ce qui change et pourquoi, et comment vous l'avez testé (surtout ce qui est visuel et que la CI ne peut pas voir).
3. Mettez à jour `README.md`, `docs/README.en.md` et `AGENTS.md` si le comportement visible change.

Les contributions sont acceptées sous la licence du projet ([MIT](LICENSE)).

## English summary

Open an issue before big features. Report vulnerabilities privately (see `SECURITY.md`). Run `test/test-e2e.sh --no-gui` before a pull request (it works in a throwaway folder and never touches your shell, your data or your Claude account unless you pass `--with-claude`). Route user-visible strings through `pick(fr, en)` / `overlay.tr(key, default)`, never auto-approve commands that can write or execute depending on their arguments, keep personal data out of the repository, and add a test for what you change. ShellCheck (`--severity=warning`) must pass.
