#!/usr/bin/env python3
"""Iris assistant daemon — bridge between the Quickshell overlay and Claude.

Runs as a long-lived child of the overlay and keeps one `claude -p` process
open in streaming mode, so a message doesn't pay the CLI start-up and MCP
connection cost (the overlay asks for a pre-warm as soon as it opens).

Speed / quota:
  * Haiku answers by default; messages that look like code or heavy work go
    to Sonnet (or force either with the mode button). The model is switched
    in place, the conversation is kept.
  * A conversation idle for SESSION_IDLE starts afresh, so the history that
    is resent with every message doesn't keep growing.

Permissions: reading files / system info / read-only connectors is
automatic; anything else (commands that change things, writing files,
creating events, fetching URLs…) is sent to the overlay as an "ask" and only
runs once the user clicks Autoriser.

Overlay → daemon (stdin, one JSON per line):
  {"cmd": "warm"}                          start Claude ahead of the first message
  {"cmd": "send", "text": "...", "mode": "auto"|"fast"|"power"}
  {"cmd": "answer", "id": "...", "allow": true|false}
  {"cmd": "stop"}                          interrupt the current reply
  {"cmd": "new"}                           start a new conversation
  {"cmd": "list"}                          → {"t": "history"}
  {"cmd": "load", "id": "..."}             → {"t": "conversation"}
  {"cmd": "delete", "id": "..."}           → {"t": "history"}
  {"cmd": "nudge", "text": "..."}          alert from iris-watch.py → {"t": "nudge"}

Daemon → overlay (stdout, one JSON per line):
  {"t": "conversation", "id", "messages": [{role, text}]}
  {"t": "model", "v": "haiku"|"sonnet"}
  {"t": "text", "v": "..."}                streamed reply chunk
  {"t": "tool", "v": "..."}                label of the tool in use
  {"t": "ask", "id", "tool", "detail"}     permission request
  {"t": "done"}  /  {"t": "error", "v": "..."}
  {"t": "history", "v": [{id, title, updated}]}
"""
import json
import os
import subprocess
import sys
import threading
import time
import uuid
import re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import LANG, pick   # noqa: E402

DATA_DIR = os.path.expanduser("~/.local/share/qs-assistant")
HIST_DIR = os.path.join(DATA_DIR, "history")
CURRENT_FILE = os.path.join(DATA_DIR, "current")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROMPT_FILE = os.path.join(SCRIPT_DIR, "assistant-prompt.md")
CONFIG_FILE = os.path.join(DATA_DIR, "config.json")
# What Iris knows about the user; kept outside the config dir (personal).
MEMORY_FILE = os.path.join(DATA_DIR, "memory.md")
ORGANIZE = os.path.join(SCRIPT_DIR, "organize.py")
UPDATE = os.path.join(SCRIPT_DIR, "iris-update")
UPDATE_LOG = os.path.join(DATA_DIR, "update.log")
UPDATE_RESULT = os.path.join(DATA_DIR, "update-result")   # exit code of the last button update
UPDATE_RUNNING = os.path.join(DATA_DIR, "update-running")  # exists while it runs
UPDATE_AVAILABLE = os.path.join(DATA_DIR, "update-available")  # written by iris-watch

# Iris must only ever use the claude.ai Pro subscription: strip anything
# that would switch Claude Code to pay-as-you-go API billing.
BILLING_ENV = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
               "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
               "CLAUDE_CODE_USE_FOUNDRY", "AWS_BEARER_TOKEN_BEDROCK")

# ── User config (~/.local/share/qs-assistant/config.json) ────────────────
# Every key is optional; a missing or invalid one keeps its default.
DEFAULT_CONFIG = {
    "language": "fr",                # "fr", "en" or "auto" (follows $LANG)
    "user_name": "",                 # how Iris calls you (joins her prompt)
    "models": {"fast": "claude-haiku-5-5", "power": "claude-sonnet-5-5"},
    "session_idle_minutes": 30,      # idle time before a fresh conversation
    "prompt_file": "",               # replaces assistant-prompt.md if set
    "deny_read_paths": [],           # e.g. ["~/.ssh", "~/.gnupg"] (see below)
    "extra_readonly_commands": [],   # run without asking: your responsibility
    "extra_denied_commands": [],     # refused even with a click
}


def load_config():
    """Defaults overlaid with config.json; bad values are ignored (stderr)."""
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    try:
        with open(CONFIG_FILE) as f:
            user = json.load(f)
        if not isinstance(user, dict):
            raise ValueError("the top level must be an object")
    except FileNotFoundError:
        return cfg
    except (OSError, ValueError) as e:
        print(f"[iris] config.json ignored: {e}", file=sys.stderr)
        return cfg
    for key, default in DEFAULT_CONFIG.items():
        if key not in user:
            continue
        v = user[key]
        if key == "models":
            ok = isinstance(v, dict) and all(isinstance(v.get(k, default[k]), str) for k in default)
            if ok:
                cfg[key] = {k: v.get(k, default[k]) for k in default}
        elif key == "session_idle_minutes":
            ok = isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0
            if ok:
                cfg[key] = v
        elif key == "language":
            ok = isinstance(v, str) and v.strip().lower() in ("fr", "en", "auto")
            if ok:
                cfg[key] = v.strip().lower()
        elif isinstance(default, list):
            ok = isinstance(v, list) and all(isinstance(x, str) and x.strip() for x in v)
            if ok:
                cfg[key] = [x.strip() for x in v]
        else:
            ok = isinstance(v, str)
            if ok:
                cfg[key] = v.strip()
        if not ok:
            print(f"[iris] config.json: invalid '{key}' ignored", file=sys.stderr)
    return cfg


CONFIG = load_config()
if CONFIG["prompt_file"]:
    PROMPT_FILE = os.path.expanduser(CONFIG["prompt_file"])
elif LANG == "en":
    PROMPT_FILE = os.path.join(SCRIPT_DIR, "assistant-prompt.en.md")
MODELS = CONFIG["models"]
SESSION_IDLE = CONFIG["session_idle_minutes"] * 60

# Messages that deserve the strong model in "auto" mode: code and real dev
# work only (Sonnet costs several times Haiku's quota). Everything else,
# including writing, planning and tidying files, stays on Haiku.
POWER_RE = re.compile(
    r"\b(code|coder|script|bug|debug|d[ée]bug\w*|stack ?trace|compil\w*|"
    r"python|qml|lua|bash|zsh|rust|javascript|typescript|java|sql|regex|"
    r"refactor\w*|fonction|function|classe|programme|algo\w*|git|commit|"
    r"impl[ée]ment\w*|implement\w*)\b"
    r"|\.(py|js|ts|qml|lua|sh|rs|cpp|java|json|toml|conf)\b",
    re.IGNORECASE)

# ── On-demand context (quota) ────────────────────────────────────────────
# A conversation starts light: no connectors (≈20k tokens). They are
# loaded (Claude restarted on the same session) as soon as
# a message needs them, and stay for the rest of the conversation.
CONNECT_RE = re.compile(
    r"agenda|calendrier|calendar|[ée]v[ée]nement|rdv|rendez|r[ée]union|planning|"
    r"planifi|emploi du temps|aujourd'?hui|demain|hier|semaine|week-?end|"
    r"lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|ce soir|ce matin|"
    r"\bmails?\b|e-?mails?|gmail|courriel|bo[iî]te de r[ée]ception|brouillon|"
    r"r[ée]pond|m'a (écrit|envoy)|notion|\bdrive\b|google doc|"
    r"qu'est-ce que j'ai|j'ai quoi|mon programme|ma journ[ée]e|dispo|"
    # English
    r"meeting|appointment|schedule|today|tomorrow|yesterday|this week|next week|"
    r"monday|tuesday|wednesday|thursday|friday|saturday|sunday|tonight|this morning|"
    r"inbox|e-?mail|draft|reply to|wrote me|sent me|what do i have|my day|free time|available",
    re.IGNORECASE)
# Iris answers just this when she needs a connector that isn't loaded; the
# daemon then loads them and asks again (the marker is never shown).
TOOLS_MARKER = "[[OUTILS]]"
# Past this context size (tokens), the next message starts a fresh Claude
# session seeded with a short recap, so history stops growing.
CONTEXT_MAX = 60_000

# Built-in tools (fewer tools = smaller prompt = fewer tokens). MCP
# connectors (Calendar, Gmail, Notion, Drive…) come on top, trimmed to
# MCP_KEEP below.
TOOLS = "Bash,Read,Edit,Write,Glob,Grep,WebSearch,WebFetch"

# Quota: every tool schema is resent with each message, and the claude.ai
# connectors bring ~150 of them (≈100k tokens per message before trimming).
# Only these connector tools stay visible; the rest is removed from the
# context with deny rules (a denied tool is not shown to the model).
MCP_KEEP = {
    "Google_Calendar": ["list_events", "search_events", "get_event",
                        "create_event", "update_event", "delete_event"],
    "Gmail": ["search_threads", "get_thread", "create_draft"],
    "Notion": ["notion-search", "notion-fetch"],
    "Google_Drive": ["search_files", "read_file_content"],
}
MCP_DROP_SERVERS = ["Google_Sheets", "Claude_Docs", "kiwi-l_gal"]

# Runs without asking. Read-only things only; everything else goes through
# the overlay's Autoriser / Refuser card.
READONLY_BASH = [
    "ls", "cat", "head", "tail", "wc", "file", "stat", "du", "df", "free",
    "uptime", "uname", "whoami", "date", "ps", "pgrep", "lscpu", "lsblk",
    "lspci", "lsusb", "ip addr", "ip route", "ip -br", "nmcli device status",
    "nmcli -t", "nmcli connection show", "systemctl status",
    "systemctl list-units", "systemctl --user status", "journalctl",
    "pacman -Q", "pacman -Si", "which", "sensors", "hyprctl monitors",
    "hyprctl clients", "hyprctl activewindow", "hyprctl workspaces",
    "git status", "git log", "git diff", "git show", "git branch",
    "fc-list", "pwd", "grep", "wpctl status",
    "wpctl get-volume", "bluetoothctl devices", "bluetoothctl info",
]
READONLY_BASH += CONFIG["extra_readonly_commands"]
ALLOWED_TOOLS = ["Read", "Glob", "Grep", "WebSearch",
                 f"Bash(python3 {ORGANIZE} scan:*)",
                 f"Bash(bash {UPDATE} --check:*)",     # only looks, never installs
                 ] + [f"Bash({c}:*)" for c in READONLY_BASH] + [
    "mcp__claude_ai_Google_Calendar__list_calendars",
    "mcp__claude_ai_Google_Calendar__list_events",
    "mcp__claude_ai_Google_Calendar__search_events",
    "mcp__claude_ai_Google_Calendar__get_event",
    "mcp__claude_ai_Google_Calendar__suggest_time",
    "mcp__claude_ai_Gmail__search_threads",
    "mcp__claude_ai_Gmail__get_thread",
    "mcp__claude_ai_Gmail__get_message",
    "mcp__claude_ai_Gmail__list_labels",
    "mcp__claude_ai_Gmail__list_drafts",
    "mcp__claude_ai_Gmail__get_draft",
    "mcp__claude_ai_Notion__notion-search",
    "mcp__claude_ai_Notion__notion-fetch",
    "mcp__claude_ai_Google_Drive__search_files",
    "mcp__claude_ai_Google_Drive__list_recent_files",
    "mcp__claude_ai_Google_Drive__get_file_metadata",
    "mcp__claude_ai_Google_Drive__read_file_content",
]
# Never, not even with a click (sudo would also hang on its password).
DENIED_TOOLS = ["Bash(sudo:*)", "Bash(su:*)", "Bash(doas:*)",
                "Bash(dd:*)", "Bash(mkfs:*)", "Bash(wipefs:*)",
                # read-only git commands that can still write a file
                "Bash(git diff --output:*)", "Bash(git log --output:*)",
                "Bash(git show --output:*)", "Bash(git diff --ext-diff:*)"]
DENIED_TOOLS += [f"Bash({c}:*)" for c in CONFIG["extra_denied_commands"]]
# deny_read_paths: Claude Code's Read rules also cover Grep/Glob, plus the
# usual shell readers. Best effort, not a sandbox: a determined command can
# still read a file another way, but it would then need a click.
for _p in CONFIG["deny_read_paths"]:
    _p = _p.rstrip("/")
    DENIED_TOOLS += [f"Read({_p}/**)", f"Read({_p})"]
    DENIED_TOOLS += [f"Bash({c} {_p}:*)" for c in ("cat", "head", "tail", "less", "grep")]


def mcp_deny_rules(connectors=True):
    """Deny rules hiding every connector tool not listed in MCP_KEEP
    (all of them when `connectors` is False)."""
    rules = [f"mcp__claude_ai_{srv}" for srv in MCP_DROP_SERVERS]
    if not connectors:
        return rules + [f"mcp__claude_ai_{srv}" for srv in MCP_KEEP]
    names = MCP_TOOL_NAMES
    for srv, keep in MCP_KEEP.items():
        if keep is None:
            continue
        rules += [f"mcp__claude_ai_{srv}__{t}" for t in names.get(srv, []) if t not in keep]
    return rules


# Connector tool names (claude.ai), used to build the deny list above.
MCP_TOOL_NAMES = {
    "Google_Calendar": ["create_event", "delete_event", "get_event", "list_calendars",
                        "list_events", "respond_to_event", "search_events",
                        "suggest_time", "update_event"],
    "Gmail": ["apply_sensitive_message_label", "apply_sensitive_thread_label",
              "create_draft", "create_label", "delete_draft", "delete_label", "forward",
              "get_draft", "get_message", "get_thread", "label_message", "label_thread",
              "list_drafts", "list_labels", "mark_message_spam", "mark_thread_spam",
              "reply", "search_threads", "send_message", "trash_message", "trash_thread",
              "unlabel_message", "unlabel_thread", "unmark_message_spam",
              "unmark_thread_spam", "untrash_message", "untrash_thread", "update_draft",
              "update_label", "update_message_labels"],
    "Google_Drive": ["copy_file", "create_file", "download_file_content",
                     "get_file_metadata", "get_file_permissions", "list_recent_files",
                     "read_file_content", "search_files", "share_file", "trash_file",
                     "update_file"],
    "Notion": ["notion-check-mcp-next-steps", "notion-convert-page-to-skill",
               "notion-create-attachment", "notion-create-comment",
               "notion-create-database", "notion-create-file-upload",
               "notion-create-folder", "notion-create-pages", "notion-create-view",
               "notion-download-attachment", "notion-download-skill",
               "notion-duplicate-page", "notion-fetch", "notion-get-async-task",
               "notion-get-comments", "notion-get-enabled-skills",
               "notion-get-file-download-urls", "notion-get-self",
               "notion-get-session-status", "notion-get-teams", "notion-get-tool-access",
               "notion-get-users", "notion-list-favorite-pages",
               "notion-list-private-pages", "notion-list-recent-pages",
               "notion-list-session-events", "notion-list-shared-pages",
               "notion-memory-search", "notion-move-pages", "notion-query-data-sources",
               "notion-query-meeting-notes", "notion-query-multiple-data-sources",
               "notion-query-sessions", "notion-read-session-event",
               "notion-restore-pages", "notion-search", "notion-search-agents",
               "notion-search-sessions", "notion-send-message-to-session",
               "notion-show-advanced-analysis-next-steps", "notion-spawn-session",
               "notion-stop-session", "notion-update-data-source",
               "notion-update-enabled-skills", "notion-update-folder",
               "notion-update-page", "notion-update-view", "notion-upload-skill",
               "notion-wait-session"],
}

TOOL_LABELS = [
    ("Bash", pick("Je lance une commande…", "Running a command…")),
    ("Read", pick("Je regarde tes fichiers…", "Looking at your files…")),
    ("Glob", pick("Je regarde tes fichiers…", "Looking at your files…")),
    ("Grep", pick("Je fouille tes fichiers…", "Searching your files…")),
    ("Edit", pick("J'écris dans un fichier…", "Writing to a file…")),
    ("Write", pick("J'écris dans un fichier…", "Writing to a file…")),
    ("WebSearch", pick("Je cherche sur le web…", "Searching the web…")),
    ("WebFetch", pick("Je lis une page web…", "Reading a web page…")),
    ("Google_Calendar", pick("Je regarde ton agenda…", "Checking your calendar…")),
    ("Gmail", pick("Je fouille tes mails…", "Searching your mail…")),
    ("Notion", pick("Je cherche dans Notion…", "Searching Notion…")),
    ("Google_Drive", pick("Je cherche dans ton Drive…", "Searching your Drive…")),
]

_out_lock = threading.Lock()


def emit(event, /, **fields):
    obj = {"t": event, **fields}
    with _out_lock:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def tool_label(name):
    for key, label in TOOL_LABELS:
        if name == key or (name.startswith("mcp__") and key in name):
            return label
    return pick("Je réfléchis…", "Thinking…")


def organize_detail(command):
    """Render an `organize.py apply` heredoc plan as readable lines."""
    m = re.search(r"<<\s*'?(\w+)'?\n(.*)\n\1\s*$", command, re.S)
    if not m:
        return None
    try:
        plan = json.loads(m.group(2))
    except ValueError:
        return None
    home = os.path.expanduser("~")
    short = lambda p: p.replace(home, "~")
    moves, trash = plan.get("moves", []), plan.get("trash", [])
    lines = [pick(f"Rangement : {len(moves)} déplacement(s), {len(trash)} à la corbeille",
                  f"Tidy-up: {len(moves)} move(s), {len(trash)} to the trash")]
    lines += [f"{short(mv['from'])}  →  {short(mv['to'])}" for mv in moves]
    lines += [pick(f"corbeille : {short(t)}", f"trash: {short(t)}") for t in trash]
    return "\n".join(lines)


def ask_detail(tool, inp):
    """Short human-readable description of what a tool call would do."""
    if tool == "Bash":
        cmd = inp.get("command", "")
        if "organize.py apply" in cmd:
            return organize_detail(cmd) or cmd
        return cmd
    if tool in ("Edit", "Write"):
        body = inp.get("content") or inp.get("new_string") or ""
        body = body if len(body) <= 600 else body[:600] + "…"
        return inp.get("file_path", "") + ("\n" + body if body else "")
    if tool == "WebFetch":
        return inp.get("url", "")
    if tool.startswith("mcp__"):
        name = tool.split("__")[-1].replace("_", " ")
        keys = ("summary", "title", "subject", "to", "start", "query")
        bits = [f"{k}: {inp[k]}" for k in keys if isinstance(inp.get(k), (str, int))]
        return name + (" — " + ", ".join(bits) if bits else "")
    return json.dumps(inp, ensure_ascii=False)[:300]


def system_prompt(connectors=True):
    with open(PROMPT_FILE) as f:
        text = f.read().replace("{ORGANIZE}", ORGANIZE).replace("{UPDATE}", UPDATE)
    if not connectors:
        text += pick(
            "\n\nPour économiser le quota, les outils Google Calendar, Gmail, Notion et "
            "Drive ne sont pas chargés dans ce message. Si tu en as besoin pour répondre, "
            f"réponds uniquement {TOOLS_MARKER} (rien d'autre) : ils seront chargés et la "
            "question te sera reposée.",
            "\n\nTo save quota, the Google Calendar, Gmail, Notion and Drive tools are not "
            "loaded for this message. If you need them to answer, reply only "
            f"{TOOLS_MARKER} (nothing else): they will be loaded and the question asked again.")
    if CONFIG["user_name"]:
        text += pick(f"\n\nL'utilisateur s'appelle {CONFIG['user_name']}.",
                     f"\n\nThe user's name is {CONFIG['user_name']}.")
    for title, path in [(pick("Ta mémoire", "Your memory"), MEMORY_FILE)]:
        try:
            with open(path) as f:
                text += f"\n\n# {title} ({path})\n\n" + f.read()
        except OSError:
            pass
    return text


# ── Conversation history ─────────────────────────────────────────────────
class Conversation:
    def __init__(self, data=None):
        data = data or {}
        self.id = data.get("id") or uuid.uuid4().hex[:12]
        self.title = data.get("title", "")
        self.created = data.get("created", time.time())
        self.updated = data.get("updated", self.created)
        self.session = data.get("session")
        self.messages = data.get("messages", [])

    @property
    def path(self):
        return os.path.join(HIST_DIR, self.id + ".json")

    def save(self):
        if not self.messages:
            return
        self.updated = time.time()
        tmp = self.path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.__dict__, f, ensure_ascii=False)
        os.replace(tmp, self.path)
        with open(CURRENT_FILE, "w") as f:
            f.write(self.id)

    @staticmethod
    def load(cid):
        try:
            with open(os.path.join(HIST_DIR, cid + ".json")) as f:
                return Conversation(json.load(f))
        except (OSError, ValueError):
            return None


def list_history():
    out = []
    for name in os.listdir(HIST_DIR):
        if not name.endswith(".json"):
            continue
        c = Conversation.load(name[:-5])
        if c:
            out.append({"id": c.id, "title": c.title or "(sans titre)", "updated": c.updated})
    out.sort(key=lambda c: -c["updated"])
    return out


# ── Claude process ───────────────────────────────────────────────────────
class Claude:
    """One streaming `claude -p` process bound to a conversation."""

    def __init__(self, daemon, conv, model, connectors=False):
        self.daemon = daemon
        self.model = model
        self.connectors = connectors
        cmd = [
            "claude", "-p",
            "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
            "--model", model,
            # Iris's own prompt replaces Claude Code's (long, coding-oriented)
            # one, and skills are off: both are resent with every message.
            "--system-prompt", system_prompt(connectors),
            "--disable-slash-commands",
            "--tools", TOOLS,
            "--allowedTools", *ALLOWED_TOOLS,
            "--disallowedTools", *DENIED_TOOLS, *mcp_deny_rules(connectors),
            "--permission-prompt-tool", "stdio",
        ]
        if conv.session:
            cmd += ["--resume", conv.session]
        env = {k: v for k, v in os.environ.items() if k not in BILLING_ENV}
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"   # Iris has her own memory
        self.proc = subprocess.Popen(
            cmd, cwd=os.path.expanduser("~"), env=env, text=True, bufsize=1,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._req = 0
        self.send({"type": "control_request", "request_id": self._next(),
                   "request": {"subtype": "initialize"}})
        threading.Thread(target=self._read, daemon=True).start()

    def alive(self):
        return self.proc.poll() is None

    def _next(self):
        self._req += 1
        return f"px{self._req}"

    def send(self, obj):
        try:
            self.proc.stdin.write(json.dumps(obj) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            pass

    def set_model(self, model):
        if model != self.model:
            self.model = model
            self.send({"type": "control_request", "request_id": self._next(),
                       "request": {"subtype": "set_model", "model": model}})

    def user(self, text):
        self.send({"type": "user", "message": {"role": "user", "content": text},
                   "parent_tool_use_id": None, "session_id": ""})

    def interrupt(self):
        self.send({"type": "control_request", "request_id": self._next(),
                   "request": {"subtype": "interrupt"}})

    def answer(self, request_id, allow, tool_input):
        resp = ({"behavior": "allow", "updatedInput": tool_input} if allow else
                {"behavior": "deny", "message": pick("L'utilisateur a refusé cette action.", "The user denied this action.")})
        self.send({"type": "control_response", "response": {
            "subtype": "success", "request_id": request_id, "response": resp}})

    def kill(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        self.proc.terminate()

    def _read(self):
        for line in self.proc.stdout:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            self.daemon.on_event(self, d)
        self.daemon.on_exit(self, self.proc.stderr.read().strip()[-300:])


# ── Daemon ───────────────────────────────────────────────────────────────
class Daemon:
    def __init__(self):
        self.lock = threading.RLock()
        self.claude = None
        self.conv = self._restore()
        self.busy = False
        self.reply = ""
        self.hold = False         # holding text back: might be TOOLS_MARKER
        self.last_text = ""       # last user message (resent after loading tools)
        self.last_ctx = 0         # context size of the last API call (tokens)
        self.nudges = []          # alerts shown since the last message (told to Claude)
        self.queued = []          # alerts that arrived mid-reply
        self.updating = False     # the "Update" button is running iris-update
        self.pending = {}         # request_id → tool input (awaiting a click)
        # Set if Claude Code ever reports paid "extra usage": Iris then
        # refuses to send anything until restarted.
        self.overage = False

    def _restore(self):
        try:
            cid = open(CURRENT_FILE).read().strip()
        except OSError:
            return Conversation()
        conv = Conversation.load(cid)
        if not conv or time.time() - conv.updated > SESSION_IDLE:
            return Conversation()
        return conv

    def _show_conversation(self):
        emit("conversation", id=self.conv.id,
             messages=[{"role": m["role"], "text": m["text"], "kind": m.get("kind", ""),
                        # alerts saved before actions existed: "update" kind = update button
                        "action": m.get("action") or ({"id": "update"} if m.get("kind") == "update" else None)}
                       for m in self.conv.messages])

    def _ensure_claude(self, model, connectors=False):
        c = self.claude
        if c and c.alive() and (c.connectors or not connectors):
            c.set_model(model)
            return
        # (Re)start with what's needed, keeping what was already loaded.
        if c and c.alive():
            connectors = connectors or c.connectors
        self._drop_claude()
        self.claude = Claude(self, self.conv, model, connectors)

    def _recap(self):
        """Last exchanges, to seed a fresh session when the context got big."""
        lines = []
        for m in self.conv.messages[-6:]:
            who = {"user": CONFIG["user_name"] or pick("Utilisateur", "User"),
                   "nudge": pick("Iris (alerte)", "Iris (alert)")}.get(m["role"], "Iris")
            t = m["text"].strip()
            lines.append(f"{who} : {t[:500]}{'…' if len(t) > 500 else ''}")
        return (pick("(Conversation trop longue, reprise à neuf. Derniers échanges pour contexte :\n",
                     "(Conversation too long, starting afresh. Latest exchanges for context:\n")
                + "\n".join(lines) + ")\n\n")

    def _drop_claude(self):
        if self.claude:
            self.claude.kill()
            self.claude = None
        self.pending.clear()

    # Commands from the overlay
    def handle(self, cmd):
        c = cmd.get("cmd")
        with self.lock:
            if c == "warm":
                if time.time() - self.conv.updated > SESSION_IDLE and self.conv.messages:
                    self._new()
                if not (self.claude and self.claude.alive()):
                    self.claude = Claude(self, self.conv, MODELS["fast"])
            elif c == "send":
                self._send(cmd.get("text", "").strip(), cmd.get("mode", "auto"))
            elif c == "answer":
                inp = self.pending.pop(cmd.get("id"), None)
                if inp is not None and self.claude:
                    self.claude.answer(cmd["id"], bool(cmd.get("allow")), inp)
            elif c == "stop":
                if self.claude and self.busy:
                    self.claude.interrupt()
            elif c == "new":
                self._new()
            elif c == "list":
                emit("history", v=list_history())
            elif c == "load":
                conv = Conversation.load(cmd.get("id", ""))
                if conv:
                    self._drop_claude()
                    self.busy = False
                    self.last_ctx = 0
                    self.conv = conv
                    with open(CURRENT_FILE, "w") as f:
                        f.write(conv.id)
                    self._show_conversation()
            elif c == "delete":
                cid = cmd.get("id", "")
                try:
                    os.remove(os.path.join(HIST_DIR, cid + ".json"))
                except OSError:
                    pass
                if cid == self.conv.id:
                    self._new()
                emit("history", v=list_history())
            elif c == "nudge":
                if self.busy:
                    self.queued.append((cmd.get("text", ""), cmd.get("kind", ""), cmd.get("action")))
                else:
                    self._nudge(cmd.get("text", ""), cmd.get("kind", ""), cmd.get("action"))
            elif c == "update":
                self._start_update()
            elif c == "action":
                self._run_action(cmd.get("id"), cmd.get("arg"))
            elif c == "hello":
                self._show_conversation()

    def _nudge(self, text, kind="", action=None):
        """Iris speaks first: an alert from the watcher joins the chat."""
        if not text:
            return
        if self.conv.messages and time.time() - self.conv.updated > SESSION_IDLE:
            self._new()
        if not self.conv.title:
            self.conv.title = pick("Alertes d'Iris", "Iris alerts")
        action = clean_action(action)
        self.conv.messages.append({"role": "nudge", "text": text, "kind": kind, "action": action})
        self.conv.save()
        self.nudges.append(text)
        emit("nudge", v=text, kind=kind, action=action)

    # ── Alert action buttons ─────────────────────────────────────────
    # Only these ids can be run, with arguments checked here: the click is
    # the user's consent, but the overlay must not be able to ask for more.
    def _run_action(self, action_id, arg):
        if action_id == "update":
            self._start_update()
        elif action_id == "git_pull":
            threading.Thread(target=self._git_pull, args=(arg,), daemon=True).start()

    def _git_pull(self, arg):
        def done(ok, text):
            emit("action_done", id="git_pull", arg=arg, ok=ok, v=text)
        home = os.path.realpath(os.path.expanduser("~"))
        path = os.path.realpath(os.path.expanduser(arg)) if isinstance(arg, str) and arg else ""
        if not (path.startswith(home + os.sep) and os.path.isdir(path)
                and os.path.exists(os.path.join(path, ".git"))):
            return done(False, pick("Dépôt refusé (hors du dossier personnel ou pas un dépôt git).",
                                    "Repository refused (outside the home folder or not a git repo)."))
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0", LANG="C.UTF-8",
                   GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=8")
        try:
            r = subprocess.run(["git", "-C", path, "pull", "--ff-only"], capture_output=True,
                               text=True, timeout=120, env=env, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired) as e:
            return done(False, pick("git pull a échoué : ", "git pull failed: ") + str(e))
        lines = [ln for ln in (r.stdout + r.stderr).strip().splitlines() if ln.strip()]
        short = path.replace(home, "~", 1)
        if r.returncode == 0:
            return done(True, f"`git pull` — `{short}/`\n" + "\n".join(lines[-4:]))
        done(False, pick("git pull a échoué dans ", "git pull failed in ") + f"`{short}/`\n" + "\n".join(lines[-4:]))

    # ── "Update" button ──────────────────────────────────────────────
    # The installer replaces the overlay's own files, which makes Quickshell
    # reload and kill this daemon. So the update runs in its own session,
    # writes its exit code to UPDATE_RESULT, and whoever is alive at the end
    # (this process, or the next daemon at startup) reports it once.
    def _start_update(self):
        if self.updating or update_is_running():
            return
        if not os.path.isfile(UPDATE):
            emit("update_done", ok=False, v=pick("iris-update est introuvable.", "iris-update not found."))
            return
        self.updating = True
        try:
            os.remove(UPDATE_RESULT)
        except OSError:
            pass
        with open(UPDATE_RUNNING, "w") as f:
            f.write(str(time.time()))
        script = 'bash "$1" -y > "$2" 2>&1; echo $? > "$3"; rm -f "$4"'
        try:
            proc = subprocess.Popen(["bash", "-c", script, "iris-update", UPDATE, UPDATE_LOG,
                                     UPDATE_RESULT, UPDATE_RUNNING],
                                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError as e:
            self.updating = False
            emit("update_done", ok=False, v=str(e))
            return
        threading.Thread(target=self._wait_update, args=(proc,), daemon=True).start()

    def _wait_update(self, proc):
        try:
            proc.wait(timeout=600)
        except subprocess.TimeoutExpired:
            proc.kill()
        with self.lock:
            self.updating = False
            report_update_result()
            emit_update_state()

    def _new(self):
        self._drop_claude()
        self.busy = False
        self.last_ctx = 0
        self.conv = Conversation()
        try:
            os.remove(CURRENT_FILE)
        except OSError:
            pass
        self._show_conversation()

    def _send(self, text, mode):
        if not text or self.busy:
            return
        if self.overage:
            emit("error", v=pick(
                "Bloqué : ton compte passerait en usage payant (au-delà de "
                "l'abonnement Pro). Attends la remise à zéro de ta limite.",
                "Blocked: your account would switch to paid usage (beyond your "
                "subscription). Wait for your limit to reset."))
            emit("done")
            return
        if self.conv.messages and time.time() - self.conv.updated > SESSION_IDLE:
            self._new()
        if mode == "auto":
            # Once a conversation went to Sonnet it stays there: switching
            # model drops the prompt cache, and rebuilding it costs more quota
            # than answering a small message with Sonnet.
            on_sonnet = self.claude and self.claude.alive() and self.claude.model == MODELS["power"]
            mode = "power" if on_sonnet or POWER_RE.search(text) else "fast"
        emit("model", v="sonnet" if mode == "power" else "haiku")
        prefix = ""
        if self.last_ctx > CONTEXT_MAX and self.conv.messages:
            prefix = self._recap()
            self._drop_claude()
            self.conv.session = None
            self.last_ctx = 0
        self._ensure_claude(MODELS.get(mode, MODELS["fast"]),
                            connectors=bool(CONNECT_RE.search(text)))
        if not self.conv.title:
            self.conv.title = text[:60]
        self.conv.messages.append({"role": "user", "text": text})
        self.conv.save()
        self.busy = True
        self.reply = ""
        self.last_text = text
        self.hold = not self.claude.connectors
        if self.nudges:
            # Claude didn't see the alerts: tell it what the user is replying to.
            prefix += (pick("(Alertes que tu as envoyées d'elle-même à l'utilisateur juste avant, "
                            "sans qu'il te demande rien :\n",
                            "(Alerts you sent on your own to the user just before, "
                            "without being asked:\n")
                       + "\n".join(f"- {n}" for n in self.nudges) + ")\n\n")
            self.nudges = []
        self.claude.user(prefix + text)

    def _retry_with_connectors(self):
        """Iris asked for the connectors: load them and ask again."""
        emit("tool", v=pick("Je charge tes outils (agenda, mails, Notion, Drive)…",
                            "Loading your tools (calendar, mail, Notion, Drive)…"))
        model = self.claude.model
        self._ensure_claude(model, connectors=True)
        self.reply = ""
        self.hold = False
        self.claude.user(pick("(Les outils Calendar, Gmail, Notion et Drive sont maintenant "
                              "chargés.) ", "(The Calendar, Gmail, Notion and Drive tools are "
                              "now loaded.) ") + self.last_text)

    def _finish(self, error=None):
        if self.hold and self.reply:      # held back but not the marker
            emit("text", v=self.reply)
        self.hold = False
        if self.reply:
            self.conv.messages.append({"role": "assistant", "text": self.reply})
        self.conv.save()
        if error and not self.reply:
            emit("error", v=error)
        self.reply = ""
        self.busy = False
        self.pending.clear()
        emit("done")
        for text, kind, action in self.queued:
            self._nudge(text, kind, action)
        self.queued = []

    # Events from Claude (reader thread)
    def on_event(self, claude, d):
        with self.lock:
            if claude is not self.claude:
                return
            typ = d.get("type")
            if typ == "system" and d.get("subtype") == "init":
                if d.get("session_id"):
                    self.conv.session = d["session_id"]
            elif typ == "stream_event" and self.busy:
                ev = d.get("event", {})
                if ev.get("type") == "content_block_start":
                    block = ev.get("content_block", {})
                    if block.get("type") == "tool_use":
                        emit("tool", v=tool_label(block.get("name", "")))
                    elif block.get("type") == "text" and self.reply:
                        self.reply += "\n\n"
                        emit("text", v="\n\n")
                elif ev.get("type") == "content_block_delta":
                    delta = ev.get("delta", {})
                    if delta.get("type") == "text_delta" and delta.get("text"):
                        self.reply += delta["text"]
                        if not self.hold:
                            emit("text", v=delta["text"])
                        elif not TOOLS_MARKER.startswith(self.reply.strip()):
                            # Not the marker after all: release what was held.
                            self.hold = False
                            emit("text", v=self.reply)
            elif typ == "control_request":
                req = d.get("request", {})
                if req.get("subtype") == "can_use_tool":
                    rid = d.get("request_id")
                    tool = req.get("tool_name", "")
                    inp = req.get("input", {})
                    self.pending[rid] = inp
                    emit("ask", id=rid, tool=tool, detail=ask_detail(tool, inp))
            elif typ == "rate_limit_event":
                info = d.get("rate_limit_info", {})
                win = info.get("unifiedWindows", {})
                emit("usage",
                     five=win.get("five_hour", {}).get("utilization"),
                     week=win.get("seven_day", {}).get("utilization"),
                     resets=info.get("resetsAt"), status=info.get("status"))
                if info.get("isUsingOverage"):
                    # Never bill beyond the subscription: stop right here.
                    self.overage = True
                    self.claude.interrupt()
                    emit("error", v=pick(
                        "Arrêt : cette réponse aurait été facturée en usage "
                        "payant, hors abonnement Pro. Rien d'autre ne sera envoyé.",
                        "Stopped: this reply would have been billed as paid usage, "
                        "outside your subscription. Nothing else will be sent."))
            elif typ == "result" and self.busy:
                iters = (d.get("usage") or {}).get("iterations") or []
                if iters:
                    last = iters[-1]
                    self.last_ctx = sum(last.get(k, 0) for k in (
                        "input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
                if (not d.get("is_error") and self.reply.strip() == TOOLS_MARKER
                        and not self.claude.connectors):
                    self._retry_with_connectors()
                    return
                self._finish(d.get("result") if d.get("is_error") else None)

    def on_exit(self, claude, stderr):
        with self.lock:
            if claude is not self.claude:
                return
            self.claude = None
            if self.busy:
                # Resuming a vanished session fails at start: forget it so
                # the next message opens a fresh one.
                self.conv.session = None
                self._finish(stderr or pick("Claude s'est arrêté.", "Claude stopped."))


def report_update_result():
    """Tell the overlay how an "Update" button run ended, then forget it."""
    try:
        with open(UPDATE_RESULT) as f:
            code = f.read().strip()
        os.remove(UPDATE_RESULT)
    except OSError:
        return
    try:
        with open(UPDATE_LOG, errors="replace") as f:
            log = re.sub(r"\x1b\[[0-9;]*m", "", f.read()).strip().splitlines()
    except OSError:
        log = []
    if code == "0":
        try:
            with open(os.path.join(DATA_DIR, "installed-rev")) as f:
                rev = f.read().strip()[:7]
        except OSError:
            rev = ""
        emit("update_done", ok=True, v=pick("Iris est à jour", "Iris is up to date") + (f" ({rev})" if rev else "") + ".")
    else:
        emit("update_done", ok=False, v=pick("La mise à jour a échoué :\n", "The update failed:\n")
             + "\n".join(log[-6:]))


def clean_action(action):
    """Keep only a well-formed {id, label, arg} (strings), or None."""
    if not isinstance(action, dict) or not isinstance(action.get("id"), str):
        return None
    return {k: action[k] for k in ("id", "label", "arg") if isinstance(action.get(k), str)}


def update_is_running():
    try:
        return time.time() - os.path.getmtime(UPDATE_RUNNING) < 900
    except OSError:
        return False


def emit_update_state():
    """Tell the overlay whether an update is available / running (header button)."""
    emit("update_state", available=os.path.exists(UPDATE_AVAILABLE), running=update_is_running())


def watch_running_update():
    """A previous daemon started an update that is still running (Quickshell
    reloaded mid-way): report its result when it lands."""
    deadline = time.time() + 600
    while time.time() < deadline:
        if os.path.exists(UPDATE_RESULT):
            report_update_result()
            return
        time.sleep(1)


def ui_strings():
    """Texts shown by the QML overlay, sent once at startup (it falls back to
    French when it receives nothing, e.g. with an older daemon)."""
    return {
        "reset": pick("réinit. ", "resets in "),
        "greet_night": pick("Encore debout ?", "Still up?"),
        "greet_day": pick("Bonjour", "Good morning"),
        "greet_evening": pick("Bonsoir", "Good evening"),
        "thinking": pick("Je réfléchis…", "Thinking…"),
        "writing": pick("J'écris…", "Writing…"),
        "online": pick("En ligne", "Online"),
        "no_history": pick("Aucune conversation pour l'instant", "No conversations yet"),
        "chip1": pick("Qu'est-ce que j'ai aujourd'hui ?", "What's on my agenda today?"),
        "chip2": pick("Aide-moi à planifier ma semaine", "Help me plan my week"),
        "chip3": pick("Où est mon dernier PDF téléchargé ?", "Where is my last downloaded PDF?"),
        "chip4": pick("Qu'est-ce qui ralentit mon PC ?", "What is slowing down my PC?"),
        "wants": pick("Iris veut utiliser", "Iris wants to use"),
        "allow": pick("Autoriser", "Allow"),
        "deny": pick("Refuser", "Deny"),
        "update_btn": pick("Mettre à jour", "Update now"),
        "updating": pick("Mise à jour…", "Updating…"),
        "updated_state": pick("À jour", "Up to date"),
        "update_tip": pick("Mettre Iris à jour", "Update Iris"),
        "working": pick("En cours…", "Working…"),
        "done_state": pick("Fait", "Done"),
        "attached": pick("Texte joint", "Attached text"),
        "chars": pick("car.", "chars"),
        "attached_default": pick("Voici le texte que j'ai sélectionné :", "Here is the text I selected:"),
        "updating_msg": pick("Mise à jour en cours… le panneau peut se recharger.", "Updating… the panel may reload."),
        "allowed": pick("Autorisé", "Allowed"),
        "denied": pick("Refusé", "Denied"),
        "replying": pick("Iris répond…", "Iris is replying…"),
        "placeholder": pick("Demande-moi quelque chose…", "Ask me anything…"),
        "mode_fast": pick("Rapide", "Fast"),
        "mode_power": pick("Puissant", "Powerful"),
        "day_abbr": pick("j", "d"),
        "locale": pick("fr_FR", "en_US"),
        "date_fmt": pick("dddd d MMMM · HH:mm", "dddd, MMMM d · HH:mm"),
    }


def main():
    os.makedirs(HIST_DIR, exist_ok=True)
    os.chmod(DATA_DIR, 0o700)   # history holds mail/file contents
    daemon = Daemon()
    emit("ui", lang=LANG, s=ui_strings())
    daemon.handle({"cmd": "hello"})
    # An update from the "Update" button may have finished (or still run)
    # while the overlay was reloading.
    report_update_result()
    emit_update_state()
    if update_is_running():
        threading.Thread(target=watch_running_update, daemon=True).start()
    for line in sys.stdin:
        try:
            cmd = json.loads(line)
        except ValueError:
            continue
        daemon.handle(cmd)
    with daemon.lock:
        daemon._drop_claude()


if __name__ == "__main__":
    main()
