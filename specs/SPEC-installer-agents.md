# Spec : installer-agents (modèles/agents dans l'installeur, installeur et panneau plus soignés, docs)

Trois lots indépendants, dans cet ordre : `installer-agents` → `polish` (installeur puis panneau) → `docs` (tous les `.md`, avant le merge sur `main`).

## 1. installer-agents

### Objectif
Dire à l'installeur quels modèles et quels agents Iris doit avoir ; il les déclare dans `config.json` et, pour Ollama, les télécharge lui-même.

### Comportement
- **Ollama** : `--ollama-model ID` (répétable : le 1er sert de modèle rapide, le 2e de puissant, sinon le même). En interactif : « Ajouter un agent local (Ollama) ? » puis les modèles séparés par des virgules. Pour chaque modèle absent de `ollama list`, l'installeur lance `ollama pull ID` (progression visible). Écrit `agents.ollama = {"command": ["ollama","run","{model}"], "models": {"fast":…,"power":…}, "history": 8}`.
- **Autre CLI** : `--add-agent "nom=commande avec {prompt}"` (répétable), ou en interactif « Ajouter un autre agent (Gemini, Codex…) ? » : nom, commande. La commande est découpée avec `shlex` en liste JSON (jamais passée à un shell) ; l'installeur vérifie seulement que le programme existe (`command -v`), il ne l'exécute pas.
- `--no-pull` : déclare sans télécharger. `-y` ou sans terminal : **aucun téléchargement** sauf si `--ollama-model` est donné explicitement (un modèle pèse des Go).
- Fonctionne aussi sur un `config.json` existant (fusion des seules clés `agents`, sauvegarde `.iris-bak`), sans `--reconfigure`. Un agent déjà déclaré sous le même nom est conservé, sauf `--reconfigure`.
- L'agent par défaut reste `claude` (le sélecteur du panneau permet de changer) ; question « Utiliser cet agent par défaut ? » en interactif seulement.
- Ollama absent ou service arrêté : avertissement avec la marche à suivre, l'agent est quand même déclaré.

### Commandes
- Tests : `test/test-e2e.sh --no-gui` étendu (faux `ollama` dans le `PATH` qui journalise ses appels).

### Structure
`install.sh` (options, questions, fusion JSON par `python3 -I`), `integration/config.example.json` (exemple d'`agents`), `test/test-e2e.sh`, `scripts/iris-doctor` (signale un agent dont le programme est introuvable ou un modèle Ollama non téléchargé).

### Limites
- Toujours : identifiant de modèle validé (`^[A-Za-z0-9._:/-]+$`), commande stockée comme liste, `--dry-run` n'exécute ni pull ni écriture.
- Demander d'abord : tout téléchargement non demandé explicitement.
- Jamais : exécuter la commande d'un agent à l'installation, écraser `agent` ou un agent existant sans `--reconfigure`.

### Critères de réussite
- `./install.sh --ollama-model llama3.2 --ollama-model qwen2.5-coder -y` télécharge ce qui manque, écrit l'agent, la pastille du panneau propose `ollama`.
- Relancé, il ne retélécharge rien et ne réécrit rien.

## 2. polish

### Installeur
Bannière courte, étapes numérotées `[2/7]`, `✓` `!` `✗` colorés et cohérents, lignes `[dry-run]` atténuées, récapitulatif final lisible (copié, sauvegardé `.iris-bak`, agents/modèles, étapes restantes). Pas de code d'échappement si la sortie n'est pas un terminal ou si `NO_COLOR` est défini. Les tests e2e ne doivent pas casser.

### Panneau (QML)
Retouches visuelles, sans changer le comportement. Proposition (à confirmer) :
1. Pastille d'agent : point de couleur (Claude / local), menu avec marque ✓ sur l'agent actif, apparition en fondu.
2. Historique : regroupement « Aujourd'hui / Hier / Plus ancien ».
3. Indicateur de saisie animé (trois points) pendant que l'agent réfléchit.
4. Blocs de code et espacements des messages un peu plus soignés.

Tests : `test-e2e.sh` (aucune erreur QML) + vérification visuelle par vous.

## 3. docs (avant le merge sur main)
Mettre à jour tous les `.md` : `README.md`, `docs/README.en.md`, `docs/CHANGELOG.md`, `AGENTS.md` (carte du dépôt, procédure d'installation avec les nouvelles options, règles), `.github/CONTRIBUTING.md` (liste des tests), `SECURITY.md` (pièces jointes d'images, rappels, agents CLI), modèle de PR, `integration/*.md` et exemples. Vérifier que chaque option d'`install.sh --help` y est décrite et que FR et EN restent alignés.

## Questions ouvertes
1. Panneau : les 4 retouches proposées vous conviennent-elles, ou voulez-vous en retirer / ajouter ?
2. Téléchargement Ollama : « aucun pull en `-y` sauf `--ollama-model` explicite » vous va-t-il ?
