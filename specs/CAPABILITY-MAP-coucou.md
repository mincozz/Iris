# Capability Map : parité fonctionnelle avec Coucou

Référence : <https://github.com/Louis-CFM/coucou> (Swift/Tauri, Mac/iOS/Android/Windows/Linux). Iris reste un shell Quickshell (QML + Python) : on reprend les **fonctions**, pas le code. Chaque module aura sa spec `SPEC-<id>.md` après validation de cette carte.

| Module id | Responsabilité | Dépend de |
|---|---|---|
| `model-link` | Brancher n'importe quel modèle : point d'accès compatible OpenAI (Ollama, LM Studio, DeepSeek, Qwen, Gemini…) avec clé propre, choix du modèle depuis la pastille. Généralise `CommandAgent` et `--ollama-model`. | — |
| `token-budget` | Réduire les tokens par requête : prompt système allégé, cache de prompt, compactage de l'historique, routage rapide/puissant, compteur affiché. | `model-link` |
| `hook-bridge` | Socket Unix `$XDG_RUNTIME_DIR/iris.sock` + relais `scripts/iris-hook --agent NOM` (même format que `coucou_agent`) : Iris voit en direct les sessions de Claude Code, Codex, Gemini CLI… lancées dans un terminal. | — |
| `pill-active` | Bandeau actif plus gros : quand un agent travaille, la pastille s'agrandit et montre une ligne par session (outil en cours, fichier édité `+N −M`, clic = diff). | `hook-bridge` |
| `hook-approval` | Cartes **Autoriser / Refuser / Toujours** pour les `PermissionRequest` et les `AskUserQuestion` des agents externes, directement dans la pastille. | `hook-bridge`, `pill-active` |
| `mascot-stats` | Personnalité de la mascotte (réactions au poke, content en fin de tâche, endormi, étourdi) et statistiques d'usage calculées en local (requêtes, tokens, temps gagné). | — |
| `flow-dictation` | Touche maintenue → micro → transcription locale (whisper.cpp ou faster-whisper) → texte collé là où on écrit. Dictionnaire de mots et nettoyage optionnel par le modèle. | `model-link` (nettoyage seulement) |
| `notetaker` | Enregistrer micro + sortie audio du système, transcrire, puis résumé / points clés / to-dos par le modèle. Audio supprimé après transcription. | `flow-dictation` (moteur de transcription), `model-link` |

Ordre de construction :
`model-link` → `token-budget` ; `hook-bridge` → `pill-active` → `hook-approval` ; `mascot-stats` ; `flow-dictation` → `notetaker`.
Les quatre branches sont indépendantes. Pas de cycle.

## Hors périmètre (volontairement)
Encoche macOS, iPhone / Android / Dynamic Island, portefeuille crypto, intégrations Stripe / n8n / Vercel / Notion / Cal.com, WhatsApp, Spotify, assistant vocal avec mot d'éveil, mises à jour automatiques façon Sparkle. Dis-moi si l'une doit rentrer.

## Hypothèses (à corriger maintenant)
1. **Plateforme** : Linux / Wayland (Hyprland), Quickshell. Pas de port Mac.
2. **« Bandeau actif et plus gros »** : je l'interprète comme *la pastille de `SPEC-buddy` qui grossit et affiche les sessions d'agents en cours*, et non un nouveau widget. Elle redevient discrète au repos.
3. **« Optimisation des tokens (requêtes) parfaite »** n'est pas testable. Je le traduis en critères mesurables : tokens d'entrée par tour **−40 % ou plus** sur une conversation type de 10 tours, un compteur en pastille, et zéro régression des tests de sécurité. Le chiffre est à confirmer.
4. **« Modèle libre à relier à Iris »** : n'importe quel serveur compatible OpenAI (`base_url` + clé + id de modèle) déclaré dans `config.json`. La clé reste dans un fichier en `0600`, jamais injectée dans l'environnement de `claude` (`BILLING_ENV` inchangé). Les modèles non-Claude n'ont **pas d'outils** (comme `CommandAgent`) sauf demande contraire.
5. **Dictée** : la touche maintenue passe par un raccourci Hyprland (`bind` + `bindr`, press / release), la transcription est 100 % locale par défaut, le collage utilise `wl-copy` + `wtype`. Quels binaires sont installés reste à vérifier.
6. **Notetaker** : capture via PipeWire (`pw-record` sur le micro et sur le *monitor* du sink). Un message rappelle de prévenir les personnes de l'appel.
7. **Hooks** : le relais n'écrit que sur le socket (permissions `0600`, utilisateur courant). Une session externe est une **donnée** : son texte n'est jamais une instruction pour Iris. `PermissionRequest` n'est répondu qu'après un clic explicite, avec délai d'attente qui rend la main au terminal.
8. Règles du dépôt conservées : tout ce qui modifie passe par Autoriser / Refuser, `READONLY_BASH`, `BILLING_ENV` et les commandes interdites ne bougent pas ; textes via `pick(fr, en)` / `overlay.tr(...)` ; un test dans `test/` par module ; README FR/EN et `CHANGELOG.md` mis à jour.

## Décisions (validées le 2026-10-29)
- Cible tokens : **−40 %** d'entrée sur 10 tours.
- « Bandeau actif » = la pastille qui grossit avec les sessions **et** le design du bandeau actuel revu.
- `flow-dictation` et `notetaker` en **dernier** (pas de GPU : moteur de transcription CPU à choisir à ce moment-là).
- `hook-bridge` : Claude Code seulement pour l'instant, mais l'agent est un champ (`--agent NOM`, comme `coucou_agent`) pour en ajouter d'autres sans refonte.
- **Une branche par module**, partie de `main`, nommée `feat/<module-id>`. **Aucune ligne de co-auteur** dans les commits ni les PR.
