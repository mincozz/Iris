# Plan : model-link

Spec : `specs/SPEC-model-link.md`. Carte : `specs/CAPABILITY-MAP-coucou.md`. Tâches suivies dans `tasks/todo-model-link.md` (suivi markdown, pas de tracker externe).
Branche `feat/model-link`, créée depuis `main`. Un commit par tâche, **sans ligne de co-auteur**.

## Décisions
- **Sous-classe de `CommandAgent`** : `OpenAIAgent` réutilise `_system()` (prompt, nom, mémoire), le champ `history`, `prompt_file` et la surface `user / interrupt / answer / kill / alive / set_model`. Seuls `user()` (requête HTTP), `interrupt()` (fermeture de la socket) et le choix du modèle changent. Aucun changement côté overlay pour le streaming : les événements `text_delta` et `result` sont les mêmes.
- **`urllib` + `http.client` seulement**, aucune dépendance. Le streaming SSE se lit ligne à ligne (`data: {...}` jusqu'à `[DONE]`) ; `stop` ferme la socket depuis un autre thread. Les deltas `reasoning_content` (DeepSeek reasoner) sont ignorés.
- **Aiguillage par le contenu de l'entrée** : `type: "openai"` → `OpenAIAgent`, sinon `command` → `CommandAgent`. `valid_agent()` accepte les deux formes ; une entrée invalide est ignorée avec un message sur stderr, comme aujourd'hui.
- **Règles réseau et clé en fonctions pures** (`endpoint_ok(url)`, `read_key(path)`), testables sans serveur : `http://` seulement vers `localhost`, `127.0.0.0/8`, `::1`, `*.local` ; sinon `https://` ; pas de redirection ; clé refusée si `mode & 0o077`.
- **Mémoire** : `send_memory` vaut vrai pour un hôte local et faux sinon, sauf réglage explicite. `_system()` reçoit un paramètre pour l'omettre.
- **Pastille « distant »** : l'événement `agents` gagne un champ `remote` (bool) ; une petite pastille dans l'en-tête, texte via `overlay.tr`. Seul changement QML.
- **Reporté** : les tokens consommés par l'API (`stream_options.include_usage`) sont l'affaire de `token-budget`, pas de ce module.

## Graphe de dépendances
```
valid_agent + endpoint_ok + read_key  (T1)
        └── OpenAIAgent streaming + stop + new_agent (T2)
                ├── erreurs + délai (T3)
                └── send_memory + champ remote + pastille QML (T4)
                        ├── iris-doctor (T5)
                        ├── install.sh --add-openai (T6)
                        └── docs + exemple + CI + changelog (T7)
```
T5 et T6 sont indépendantes l'une de l'autre (fichiers différents) ; on les fait dans l'ordre pour éviter les conflits.

## Risques
| Risque | Impact | Mitigation |
|---|---|---|
| Fermer la socket pendant `readline()` ne débloque pas le thread | Haut (stop figé) | Tester `stop` avec un faux serveur qui se tait, dès T2 ; `shutdown(SHUT_RDWR)` avant `close()` |
| Fragments SSE coupés au milieu d'une ligne ou d'un caractère UTF-8 | Moyen | Décodeur incrémental et tampon de lignes, test avec fragments d'un octet |
| Serveurs qui diffèrent (Ollama, LM Studio, DeepSeek : champs `usage`, `reasoning_content`, ligne vide, `[DONE]` absent) | Moyen | Faux serveur avec ces variantes ; fin de flux = `[DONE]` **ou** fermeture propre |
| Fuite de la clé (logs, erreurs, historique, `ps`) | Haut | Clé uniquement dans l'en-tête HTTP, jamais dans une chaîne d'erreur ; test qui cherche la clé dans toute la sortie du daemon |
| Redirection vers un autre hôte avec la clé | Haut | Gestionnaire de redirection qui refuse ; test dédié |
| `http://` vers une machine du réseau local (Ollama sur un autre PC) refusé | Faible | Limite assumée par la spec ; `https://` ou tunnel. Noté dans le README |
| Mémoire envoyée par erreur à un tiers | Haut | Défaut sûr (faux hors local) + test qui inspecte le corps de la requête |
| Conflits avec `feat/coucou-style` (deux commits d'avance sur `main`) | Faible | Ce module ne touche ni la pastille ni l'avatar ; la fusion est triviale |

## Questions ouvertes
Les 4 de la spec, reprises avec leur valeur par défaut si tu ne tranches pas :
1. Mémoire vers un hôte distant : **non** par défaut.
2. Endpoint OpenAI uniquement.
3. `fast` / `power` déclarés à la main.
4. Aucun outil pour les modèles non-Claude.
