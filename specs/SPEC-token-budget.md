# Spec : token-budget

## Objectif
Réduire de **40 %** les tokens d'entrée facturés sur une conversation de 10 tours (agent `claude`), sans régression des tests de sécurité, et **afficher le compteur** dans la pastille d'agent.

## État des lieux (déjà en place, à ne pas refaire)
- Prompt système d'Iris à la place de celui de Claude Code (`--system-prompt`), skills et commandes désactivés, connecteurs MCP chargés seulement si la demande les cite (`CONNECT_RE`).
- Reprise à neuf avec récapitulatif de 6 messages au-delà de `CONTEXT_MAX` = 60 000 tokens (`last_ctx`).
- Un modèle puissant reste puissant (changer de modèle perd le cache de prompt).
- Prompt FR ≈ 5,1 Ko ; `memory.md` et les recettes y sont ajoutés.

## Mesures (2026-10-30, modèle rapide, 10 tours sans outil)
- **Baseline : 33 081** tokens d'entrée équivalents (`tasks/token-measures.jsonl`, étiquette `avant`). Le tour 1 crée ≈ 12,7 k de cache (48 % du total) ; chaque tour suivant relit ≈ 14 k.
- Contexte fixe d'un message (1 tour) : **14,1 k** = ≈ 4,4 k de prompt (9,7 k caractères, mémoire comprise) + ≈ 5,8 k d'outils (Bash, Edit, Write, WebSearch, WebFetch en tête ; `Read,Glob,Grep` seuls : 10,9 k) + ≈ 4 k incompressibles.
- Pour −40 % il faut retirer ≈ 6 k de contexte fixe : prompt réduit de moitié (≈ −2,2 k) **et** outils lourds chargés à la demande, comme les connecteurs (≈ −3,1 k). L'un sans l'autre n'y arrive pas.

## Pistes (à trancher après mesure)
1. **Mesurer d'abord** : script `test/measure-tokens.py` (hors CI, demande un compte Claude) qui rejoue 10 tours scriptés et lit `usage` de chaque `result` : `input_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`. Sortie = tableau par tour + total « équivalent d'entrée » (lecture de cache pondérée 0,1, création 1,25).
2. **Prompt allégé** : retirer les blocs rarement utiles (organize, rappels, mise à jour) du prompt de base et ne les injecter que si la demande les évoque (même mécanisme que `CONNECT_RE`).
3. **Seuil de reprise plus bas** : `CONTEXT_MAX` 60 000 → valeur mesurée, récapitulatif plus riche que 6 × 500 caractères si besoin.
4. **Compteur** : `last_ctx` et total de session envoyés à l'overlay (`usage` / nouvelle clé `ctx`), affichés dans la pastille d'agent (« 12 k »), tooltip : total de la conversation.
5. Hors périmètre : routage rapide / puissant (déjà là), troncature des sorties d'outils (touche la sécurité).

## Critères de réussite
- Baseline et résultat mesurés avec le même script, même scénario : **−40 % d'entrée équivalente** sur 10 tours.
- `test-security.py`, `test-agent.py` et e2e verts, aucune règle de `AGENTS.md` assouplie.
- Le compteur de la pastille suit `last_ctx` (test sur un `result` simulé).

## Limites
- Toujours : mesurer avant de coder ; chaque piste garde ou améliore le résultat du script.
- Demander d'abord : tout changement du prompt qui touche aux règles de sécurité ou aux cartes Autoriser / Refuser.
- Jamais : retirer une règle de sécurité du prompt pour gagner des tokens ; envoyer `memory.md` plus largement.

## Coût de la mesure
10 tours ≈ une fraction du quota 5 h ; à lancer deux fois (avant / après), sur le modèle rapide.
