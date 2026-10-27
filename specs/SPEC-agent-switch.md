# Spec : agent-switch

## Objectif
Changer d'agent (Claude, Ollama, Gemini… ceux de `agents` dans `config.json`) depuis le panneau, sans éditer le fichier ni redémarrer.

## Comportement
- Une pastille dans le panneau affiche l'agent actuel (`claude`, `ollama`…) ; un clic ouvre la liste : `claude` + les clés de `agents`. Rien à afficher (pastille masquée) s'il n'y a que `claude`.
- Choisir un agent : le daemon arrête l'agent en cours, active le nouveau, confirme par un message discret dans le chat (« Agent : ollama »). Le choix est **mémorisé** dans `~/.local/share/qs-assistant/agent` (une ligne) et lu au démarrage ; il l'emporte sur `agent` de `config.json`. Un nom inconnu ou disparu de `agents` retombe sur `claude`.
- Refusé pendant qu'Iris répond (bouton grisé).
- La liste des agents reste déclarée à la main dans `config.json` (on ne l'édite pas depuis le panneau).
- Le sélecteur de modèle Auto / Rapide / Puissant et le reste du panneau suivent l'agent choisi (jauges de quota et images : seulement pour `claude`, comme aujourd'hui).

## Commandes
- Tests : `python3 -I test/test-agent-switch.py` (daemon réel, `HOME` jetable, faux agent en `printf`). CI : `py_compile` + étape de test.

## Structure
- `scripts/assistant.py` : commande `{cmd:"agent", name}` ; événement `agents {v:[noms], current}` envoyé au démarrage, à `hello` et après un changement ; `AGENT` devient modifiable (`set_agent`), fichier d'état lu au démarrage.
- `overlays/AssistantOverlay.qml` : pastille + petit menu dans l'en-tête.
- `ui_strings()` (`agent_tip`, `agent_switched`), README FR/EN (section « Autre agent »), CHANGELOG, `test/test-agent-switch.py`.

## Style
`pick(fr, en)` / `overlay.tr()` ; même gabarit que les boutons d'en-tête et le sélecteur de modèle ; écriture du fichier d'état atomique (`.tmp` + `os.replace`).

## Tests
Nom valide : événement `agents` avec `current` mis à jour, fichier écrit, et le message suivant part bien vers le nouvel agent. Nom inconnu : ignoré. Démarrage avec fichier d'état : agent restauré ; avec un nom disparu : retour à `claude`. Changement pendant une réponse : refusé.

## Limites
- Toujours : valider le nom contre `agents` côté daemon (l'overlay ne peut pas lancer une commande arbitraire), n'écrire que le fichier d'état.
- Demander d'abord : modifier `config.json` depuis le panneau, créer ou éditer des agents depuis l'interface.
- Jamais : changer les règles de sécurité d'un agent (un agent CLI n'a toujours pas de cartes Autoriser / Refuser).
- `shortcut:` le fichier d'état est un simple nom d'agent ; passer à du JSON si d'autres réglages doivent être mémorisés.

## Critères de réussite
- Depuis le panneau : `claude` → `ollama` → `claude`, chaque message part vers le bon agent.
- Après redémarrage de Quickshell, l'agent choisi est conservé.
- `config.json` n'est jamais modifié.

## Questions ouvertes
1. **Conversation en cours au changement** : (a) on continue la même conversation (le nouvel agent reçoit l'historique récent en texte ; Claude reprend sa session), ou (b) on démarre une nouvelle conversation à chaque changement ? Je recommande (a).
2. **Mémorisation** : fichier d'état à part, comme ci-dessus (recommandé), ou réécrire `agent` dans `config.json` ?
3. **Emplacement** : pastille dans l'en-tête à côté de l'historique (recommandé), ou à côté du sélecteur Auto / Rapide / Puissant ?
