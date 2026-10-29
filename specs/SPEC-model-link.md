# Spec : model-link

## Objectif
Relier à Iris **n'importe quel modèle** exposant une API compatible OpenAI (`/v1/chat/completions`, streaming) : Ollama, LM Studio, DeepSeek, Qwen, Moonshot, Gemini (endpoint OpenAI), OpenRouter… Aujourd'hui un agent non-Claude n'existe que sous forme de commande CLI (`CommandAgent`) : pas de clé d'API, pas de vrai streaming, pas de liste de modèles. Ici, on déclare un point d'accès, on choisit le modèle depuis le panneau, et la réponse arrive token par token.

## Comportement
1. `config.json` accepte, dans `agents`, une entrée de type `openai` :
   ```json
   "agents": {
     "ollama":   {"type": "openai", "base_url": "http://localhost:11434/v1",
                  "models": {"fast": "qwen3:4b", "power": "qwen3:14b"}},
     "deepseek": {"type": "openai", "base_url": "https://api.deepseek.com/v1",
                  "key_file": "~/.config/iris/deepseek.key",
                  "models": {"fast": "deepseek-chat", "power": "deepseek-reasoner"}}
   }
   ```
   Une entrée avec `command` reste un `CommandAgent` (inchangé). Clés optionnelles : `history` (messages passés renvoyés, défaut 8), `prompt_file`, `timeout` (secondes sans octet, défaut 60), `send_memory` (voir Sécurité).
2. Le sélecteur d'agent (`SPEC-agent-switch`) liste ces agents ; le sélecteur Auto / Rapide / Puissant choisit `models.fast` ou `models.power`.
3. Réponse en streaming SSE : chaque `delta.content` devient un événement `text_delta`, exactement comme Claude et `CommandAgent`, donc l'overlay ne change pas. `stop` ferme la connexion.
4. Erreurs lisibles dans le chat : connexion refusée (« Ollama est-il lancé ? »), 401/403 (clé), 404 (modèle inconnu), 429, délai dépassé. Jamais de trace Python ni de clé affichée.
5. Un modèle non-Claude n'a **aucun outil** : pas de cartes Autoriser / Refuser, pas d'images (message clair), jauges de quota masquées. Même contrat que `CommandAgent`.
6. `iris-doctor` ajoute une ligne par agent `openai` : point d'accès joignable (`GET /models`, 3 s), clé présente et en `0600`, modèles déclarés présents dans la réponse quand elle les liste.
7. `install.sh --add-openai "nom=base_url,fast=ID,power=ID[,key_file=CHEMIN]"` écrit l'entrée sans rien exécuter ni télécharger.

## Commandes
```
Test   : python3 -I test/test-model-link.py          # faux serveur HTTP local, sans compte ni réseau
Tous   : for t in test/test-*.py; do python3 -I "$t"; done && test/test-e2e.sh --no-gui
Compile: python3 -m py_compile scripts/assistant.py scripts/iris-doctor
Lint   : qmllint overlays/*.qml     # inchangé : aucun QML attendu
```

## Structure
- `scripts/assistant.py` : classe `OpenAIAgent` (même surface que `CommandAgent` : `user`, `stop`, `set_model`, `alive`) ; `agent_for(name)` choisit la classe selon `type` / `command`. Client en `urllib` + `http.client` (stdlib, **aucune dépendance**).
- `scripts/iris-doctor`, `install.sh` : voir comportement 6 et 7.
- `integration/config.example.json`, README FR/EN (section « Autre modèle »), `CHANGELOG.md`, `AGENTS.md` (carte + règles).
- `test/test-model-link.py` + étape CI.

## Style
Mêmes conventions que `CommandAgent` : thread par réponse, événements via `daemon.on_event`, textes visibles par `pick(fr, en)`, erreurs rendues par `self._result(message)`.
```python
def _error(self, status, body):
    if status in (401, 403):
        return pick("Clé refusée par le serveur.", "The server rejected the key.")
    ...
```

## Sécurité
- **Clé d'API** : jamais dans `config.json` ni dans le dépôt ; fichier `key_file`, refusé s'il est lisible par le groupe ou les autres (`mode & 0o077`). Jamais écrite dans les logs, l'historique ou un événement. `BILLING_ENV` reste appliqué à `claude` et n'est pas assoupli.
- **Réseau** : `http://` seulement vers `localhost`, `127.0.0.0/8`, `::1` ou `*.local` ; tout le reste exige `https://`. Pas de suivi de redirection vers un autre hôte. Le corps de réponse est borné (taille et durée).
- **Données envoyées à un tiers** : un point d'accès distant reçoit le prompt, l'historique récent et, si `send_memory` est vrai, `memory.md`. **Défaut : `send_memory` faux pour un hôte non local**, vrai pour un hôte local. Le panneau affiche une pastille « distant » quand l'agent actif n'est pas local.
- La réponse du modèle est une donnée : aucune exécution, aucun outil. Le contenu des mails, pages et fichiers reste une donnée.
- Aucun changement à `READONLY_BASH`, aux commandes interdites ni à la règle Autoriser / Refuser.

## Limites
- **Toujours** : valider `type`, `base_url`, `key_file` au chargement et ignorer proprement une entrée invalide (message sur stderr, repli sur `claude`) ; tests sans réseau.
- **Demander d'abord** : ajouter une dépendance (ex. `openai`, `httpx`), donner des outils à un modèle non-Claude, envoyer la mémoire à un hôte distant.
- **Jamais** : lire ou copier une clé hors du `key_file` déclaré, la mettre dans l'environnement d'un sous-processus, relâcher les règles de sécurité d'un agent.

## Critères de réussite
- Avec un faux serveur OpenAI local, une réponse en plusieurs fragments arrive comme plusieurs `text_delta` puis un résultat, et `stop` coupe la connexion.
- Avec Ollama réel (si présent) : question → réponse streamée dans le panneau, bascule `claude` ↔ `ollama` sans redémarrage.
- 401, 404, refus de connexion et délai donnent chacun un message clair sans clé ni trace.
- `key_file` en `0644` est refusé ; `http://exemple.com` est refusé ; `http://localhost` est accepté.
- Hôte distant : `memory.md` absent de la requête par défaut.
- Tous les tests existants passent, sans modification de `READONLY_BASH` ni `BILLING_ENV`.

## Questions ouvertes
1. **Mémoire vers un hôte distant** : le défaut « non » te convient-il (Iris sera moins personnalisée avec DeepSeek que sur Ollama) ?
2. **Anthropic / Gemini natifs** : l'endpoint OpenAI suffit-il, ou veux-tu aussi le format natif d'un fournisseur ?
3. **Liste de modèles** : `fast` / `power` déclarés à la main (recommandé, simple), ou liste récupérée via `GET /models` pour choisir dans le panneau ?
4. **Outils** : un modèle local ne reçoit aucun outil pour l'instant. Un module ultérieur pourrait lui en donner (avec cartes Autoriser / Refuser) : à garder en tête ou à écarter ?
