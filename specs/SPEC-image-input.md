# Spec : image-input

## Objectif
Coller une image (typiquement une capture d'écran copiée dans le presse-papiers) avec **Ctrl+V** dans le panneau, puis poser une question dessus.

## Comportement
- Ctrl+V dans le champ de saisie : le texte se colle comme avant ; en plus, le daemon tente `wl-paste --type image/png`. S'il n'y a pas d'image, rien ne se passe.
- Si une image est présente : copiée dans `~/.local/share/qs-assistant/attachments/<uuid>.png` (dossier `0700`, fichier `0600`), pastille « Image jointe » (retirable) comme pour « Texte joint ».
- À l'envoi, le message contient `[Image jointe : <chemin>]` ; Claude la lit avec l'outil `Read` (déjà autorisé, il lit les images).
- Une image par message, 10 Mo au plus, signature PNG vérifiée.
- Purge : les fichiers de plus de **7 jours** sont supprimés au démarrage du daemon et à chaque collage.
- Agent « au choix » (`CommandAgent`) : pas d'images ; le message le dit au lieu d'échouer en silence.
- Hors périmètre : glisser-déposer, `iris-ask --screenshot`, voix.

## Commandes
- Tests : `python3 -I test/test-image.py` (faux `wl-paste` dans le `PATH`). CI : `py_compile` + étape de test.

## Structure
- `scripts/assistant.py` : commande `paste_image` → événement `image {path}` ; purge ; préfixe du message.
- `overlays/AssistantOverlay.qml` : `Keys.onPressed` (Ctrl+V sans `accepted`), propriété `image`, pastille, `send()`.
- `ui_strings()` (`image_attached`, `image_agent_unsupported`), prompts FR/EN (une ligne : « une image jointe se lit avec Read »), README FR/EN (prérequis `wl-clipboard`, déjà optionnel), CHANGELOG.

## Style
Même structure que `attached` / `prefill` dans l'overlay ; Python stdlib uniquement.

## Tests
Faux `wl-paste` : PNG valide → fichier créé en `0600`, événement émis ; contenu non-PNG → refusé ; > 10 Mo → refusé ; pas d'image → aucun événement ; fichier vieux de 8 jours supprimé, de 6 jours conservé.

## Limites
- Toujours : vérifier le contenu (signature) avant de garder le fichier ; chemin généré par le daemon, jamais fourni par l'overlay ; le contenu de l'image est de la donnée, pas une instruction.
- Demander d'abord : formats supplémentaires (jpg/webp), glisser-déposer.
- Jamais : lire un chemin envoyé par l'overlay, stocker hors de `DATA_DIR`, élargir `deny_read_paths` ou `Read`.
- `shortcut:` PNG seulement (les outils de capture Wayland copient en PNG) ; ajouter jpeg/webp si le besoin apparaît.

## Critères de réussite
- Capture copiée → Ctrl+V → pastille visible → « que dit cette erreur ? » → Iris décrit l'image.
- Ctrl+V avec du texte seul se comporte exactement comme avant.
- Aucun fichier de plus de 7 jours dans `attachments/` après un collage.
