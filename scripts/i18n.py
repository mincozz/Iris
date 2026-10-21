"""Language selection shared by Iris's scripts (French and English).

The language comes, in this order, from the IRIS_LANG environment variable,
then from "language" in ~/.local/share/qs-assistant/config.json: "fr"
(default), "en", or "auto" (follows $LC_ALL / $LC_MESSAGES / $LANG).

    from i18n import pick, LANG
    pick("Bonjour", "Hello")
"""
import json
import os

CONFIG_FILE = os.path.expanduser("~/.local/share/qs-assistant/config.json")
SUPPORTED = ("fr", "en")


def _from_env():
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        v = os.environ.get(var, "")
        if v and v not in ("C", "POSIX"):
            return "en" if v.lower().startswith("en") else "fr"
    return "fr"


def language():
    value = os.environ.get("IRIS_LANG", "").strip().lower()
    if not value:
        try:
            with open(CONFIG_FILE) as f:
                value = str(json.load(f).get("language", "fr")).strip().lower()
        except (OSError, ValueError, AttributeError):
            value = "fr"
    if value == "auto":
        return _from_env()
    return value if value in SUPPORTED else "fr"


LANG = language()


def pick(fr, en):
    """The French or English text, depending on the configured language."""
    return en if LANG == "en" else fr
