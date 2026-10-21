#!/usr/bin/env python3
"""Iris watcher — things worth telling the user without being asked.

Runs next to the assistant daemon (started by the overlay) and prints one
JSON line per alert on stdout: {"t": "nudge", "kind", "text"}. The overlay
puts it in Iris's chat and shows a notification. Everything here is local
(git, disk, battery, pacman, an iCal feed): it costs no Claude quota.

Only the Claude agenda read (above) uses quota; every other check is free.

Checks:
  git_behind    every 10 min: `git fetch` each project; new commits upstream
                → "tu devrais git pull"
  git_unpushed  once a day after 19:00: uncommitted changes / unpushed
                commits in repos touched in the last 14 days
  calendar      every 5 min: events starting within 15 min. Source: the
                secret iCal address if "ics_url" is set; otherwise (e.g. a
                Workspace that disables it) Iris reads the agenda through
                Claude's Calendar connector, at most every 3 h between 7 and
                22 h (≈12k Haiku tokens per read, a single tool loaded), and
                reminders are then computed locally.
  morning       every 10 min: once a day from "morning_hour" (default 8 h, null
                to disable), a brief: today's agenda + git work left unsaved.
                "calendar_via_claude": false keeps Claude out of the agenda.
  updates       every 6 h: `git fetch` of the clone Iris was installed from;
                tells you when a new version is out ("check_updates": false
                to disable). `iris-update` then installs it.
  health        every 15 min: disk > 90 %, battery < 15 % on battery,
                failed systemd units, > 80 pending updates (weekly)

Config / state: ~/.local/share/qs-assistant/watch.json
  {"ics_url": "https://calendar.google.com/calendar/ical/.../basic.ics",
   "repo_roots": ["~"], "exclude": ["Downloads", ...], "remind_minutes": 15}
Test one check now: iris-watch.py --once git_behind
"""
import concurrent.futures as cf
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import pick, user_name   # noqa: E402

DATA_DIR = os.path.expanduser("~/.local/share/qs-assistant")
CONFIG = os.path.join(DATA_DIR, "watch.json")
HOME = os.path.expanduser("~")

def _detect_tz():
    """The machine's IANA zone (TZ, then /etc/localtime), or None."""
    name = os.environ.get("TZ", "").lstrip(":")
    if not name:
        try:
            name = os.path.realpath("/etc/localtime").split("zoneinfo/", 1)[1]
        except (IndexError, OSError):
            name = ""
    try:
        return ZoneInfo(name) if name else None
    except Exception:       # noqa: BLE001 — unknown zone name
        return None


# Local time zone: used for all-day events, floating times and the agenda
# prompt. "timezone" in watch.json (e.g. "America/New_York") overrides it.
TZ = _detect_tz() or dt.datetime.now().astimezone().tzinfo


def tz_name():
    return getattr(TZ, "key", None) or str(TZ)


DEFAULTS = {
    "ics_url": "",
    "calendar_refresh_hours": 3,
    "repo_roots": ["~"],
    # Path parts that disqualify a repo (third-party clones, tools…).
    "exclude": ["Downloads", "Téléchargements", "node_modules", ".oh-my-zsh",
                ".cache", ".local"],
    "timezone": "",                  # IANA name; empty = this machine's zone
    "remind_minutes": 15,
    "unpushed_hour": 19,
    "morning_hour": 8,               # daily brief from this hour (null = off)
    "calendar_via_claude": True,     # False: never read the agenda through Claude
    "check_updates": True,           # tell me when a new Iris version is out
}

GIT_ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0", LANG="C.UTF-8",
               GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=8")


# ── State ────────────────────────────────────────────────────────────────
def load():
    try:
        with open(CONFIG) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    for k, v in DEFAULTS.items():
        data.setdefault(k, v)
    global TZ
    if isinstance(data.get("timezone"), str) and data["timezone"].strip():
        try:
            TZ = ZoneInfo(data["timezone"].strip())
        except Exception:   # noqa: BLE001 — bad name: keep the detected zone
            pass
    data.setdefault("seen", {})
    return data


def save(data):
    # Forget alerts older than 30 days so the file stays small.
    cut = time.time() - 30 * 86400
    data["seen"] = {k: t for k, t in data["seen"].items() if t > cut}
    tmp = CONFIG + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, CONFIG)


def nudge(state, key, kind, text, action=None):
    """Emit an alert once per key. `action` = {"id", "label", "arg"} adds a
    button to the alert (ids the daemon knows: "update", "git_pull")."""
    if key in state["seen"]:
        return
    state["seen"][key] = time.time()
    msg = {"t": "nudge", "kind": kind, "text": text}
    if action:
        msg["action"] = action
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def short(path):
    return path.replace(HOME, "~", 1)


def run(cmd, cwd=None, timeout=20):
    try:
        r = subprocess.run(cmd, cwd=cwd, env=GIT_ENV, capture_output=True,
                           text=True, timeout=timeout)
        return r.returncode, r.stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return 1, ""


# ── Git ──────────────────────────────────────────────────────────────────
def find_repos(state):
    repos = []
    for root in state["repo_roots"]:
        root = os.path.expanduser(root)
        for dirpath, dirnames, _ in os.walk(root):
            depth = dirpath[len(root):].count(os.sep)
            if ".git" in dirnames:
                repos.append(dirpath)
                dirnames.clear()
                continue
            dirnames[:] = [d for d in dirnames
                           if not d.startswith(".") and d not in state["exclude"]]
            if depth >= 5:
                dirnames.clear()
    return [r for r in repos if not any(p in r.split(os.sep) for p in state["exclude"])]


def check_git_behind(state):
    own = source_repo() if state.get("check_updates", True) else None

    def one(repo):
        if own and os.path.realpath(repo) == os.path.realpath(own):
            return None          # Iris's own clone: check_updates reports it
        # Only active projects (local commit in the last 90 days): old
        # school repos would otherwise nag forever.
        _, last = run(["git", "log", "-1", "--format=%ct"], cwd=repo)
        if not last.isdigit() or time.time() - int(last) > 90 * 86400:
            return None
        code, _ = run(["git", "fetch", "--quiet"], cwd=repo, timeout=30)
        if code:
            return None
        code, behind = run(["git", "rev-list", "--count", "HEAD..@{u}"], cwd=repo)
        if code or not behind.isdigit() or int(behind) == 0:
            return None
        _, upstream = run(["git", "rev-parse", "@{u}"], cwd=repo)
        _, authors = run(["git", "log", "--format=%an", "HEAD..@{u}"], cwd=repo)
        _, branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo)
        _, last = run(["git", "log", "-1", "--format=%s", "@{u}"], cwd=repo)
        _, dirty = run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=repo)
        return repo, int(behind), upstream, authors, branch, last, bool(dirty)

    with cf.ThreadPoolExecutor(4) as ex:
        for res in ex.map(one, find_repos(state)):
            if not res:
                continue
            repo, n, upstream, authors, branch, last, dirty = res
            who = ", ".join(dict.fromkeys(a for a in authors.splitlines() if a))
            text = (f" " + pick(
                f"**Nouveau push sur {os.path.basename(repo)}** : "
                f"{n} commit{'s' if n > 1 else ''} de {who} sur `{branch}` "
                f"(dernier : « {last[:70]} »).\n\nTu devrais faire un `git pull` "
                f"dans `{short(repo)}/`.",
                f"**New push on {os.path.basename(repo)}**: "
                f"{n} commit{'s' if n > 1 else ''} by {who} on `{branch}` "
                f"(latest: “{last[:70]}”).\n\nYou should run `git pull` "
                f"in `{short(repo)}/`."))
            if dirty:
                text += pick(" Attention, tu as des modifs locales non commitées.",
                         " Careful: you have uncommitted local changes.")
            nudge(state, f"behind:{repo}:{upstream}", "git", text,
                  {"id": "git_pull", "arg": repo, "label": pick("Faire le git pull", "Run git pull")})


def unpushed_lines(state):
    """One line per recently-touched repo with uncommitted or unpushed work."""
    lines = []
    for repo in find_repos(state):
        # Only projects touched recently (commit or working tree).
        _, last = run(["git", "log", "-1", "--format=%ct"], cwd=repo)
        _, status = run(["git", "status", "--porcelain"], cwd=repo)
        recent = last.isdigit() and time.time() - int(last) < 14 * 86400
        if not (recent or status):
            continue
        if status and not recent:
            # Old repo with stray files: only if a file changed in 14 days.
            newest = 0
            for ln in status.splitlines()[:50]:
                p = os.path.join(repo, ln[3:].split(" -> ")[-1].strip('"'))
                try:
                    newest = max(newest, os.path.getmtime(p))
                except OSError:
                    pass
            if time.time() - newest > 14 * 86400:
                continue
        _, ahead = run(["git", "rev-list", "--count", "@{u}..HEAD"], cwd=repo)
        bits = []
        changed = len(status.splitlines()) if status else 0
        if changed:
            bits.append(pick(f"{changed} fichier{'s' if changed > 1 else ''} modifié{'s' if changed > 1 else ''} non commité{'s' if changed > 1 else ''}",
                             f"{changed} uncommitted file{'s' if changed > 1 else ''}"))
        if ahead.isdigit() and int(ahead):
            bits.append(pick(f"{ahead} commit{'s' if int(ahead) > 1 else ''} pas encore push",
                             f"{ahead} commit{'s' if int(ahead) > 1 else ''} not pushed yet"))
        if bits:
            lines.append(f"- `{short(repo)}/` : " + ", ".join(bits))
    return lines


def check_git_unpushed(state):
    now = dt.datetime.now()
    if now.hour < state["unpushed_hour"]:
        return
    key = f"unpushed:{now.date()}"
    if key in state["seen"]:
        return
    lines = unpushed_lines(state)
    state["seen"][key] = time.time()
    if lines:
        nudge(state, key + ":sent", "git",
              " " + pick("**Avant de finir ta journée**, du travail n'est pas sauvegardé sur git :\n\n",
                          "**Before you wrap up**, some work is not saved on git:\n\n")
              + "\n".join(lines))


# ── Calendar (iCal feed) ─────────────────────────────────────────────────
def _unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def _parse_dt(value, params):
    tz = None
    m = re.search(r"TZID=([^;:]+)", params)
    if m:
        try:
            tz = ZoneInfo(m.group(1))
        except Exception:
            tz = None
    if re.fullmatch(r"\d{8}", value):                  # all-day
        return dt.datetime.strptime(value, "%Y%m%d").replace(tzinfo=TZ), True
    if value.endswith("Z"):
        return dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc), False
    d = dt.datetime.strptime(value, "%Y%m%dT%H%M%S")
    return d.replace(tzinfo=tz or TZ), False


def upcoming_events(ics, start, end):
    """(uid, start, summary, location) of timed events starting in [start, end]."""
    from dateutil.rrule import rrulestr
    events, ev = [], None
    for line in _unfold(ics):
        if line == "BEGIN:VEVENT":
            ev = {"exdate": []}
        elif line == "END:VEVENT" and ev is not None:
            events.append(ev)
            ev = None
        elif ev is not None and ":" in line:
            head, value = line.split(":", 1)
            name, _, params = head.partition(";")
            value = value.replace("\\,", ",").replace("\\n", " ").replace("\\;", ";")
            try:
                if name == "DTSTART":
                    ev["start"], ev["allday"] = _parse_dt(value, params)
                elif name == "RRULE":
                    ev["rrule"] = value
                elif name == "EXDATE":
                    ev["exdate"] += [_parse_dt(v, params)[0] for v in value.split(",")]
                elif name == "RECURRENCE-ID":
                    ev["recurrence"] = _parse_dt(value, params)[0]
                elif name in ("SUMMARY", "LOCATION", "UID", "STATUS"):
                    ev[name.lower()] = value
            except ValueError:
                pass
    # Occurrences moved or cancelled one by one (RECURRENCE-ID) replace the
    # matching occurrence of their series.
    moved = {(e.get("uid"), e["recurrence"]) for e in events if "recurrence" in e}
    out = []
    for e in events:
        if "start" not in e or e.get("allday") or e.get("status") == "CANCELLED":
            continue
        starts = [e["start"]]
        if e.get("rrule") and "recurrence" not in e:
            try:
                rule = rrulestr(e["rrule"], dtstart=e["start"])
                starts = rule.between(start - dt.timedelta(minutes=1), end, inc=True)
            except (ValueError, TypeError):
                pass
            starts = [x for x in starts if (e.get("uid"), x) not in moved]
        for x in starts:
            if start <= x <= end and x not in e["exdate"]:
                out.append((e.get("uid", ""), x, e.get("summary", pick("Événement", "Event")), e.get("location", "")))
    return out


CAL_CACHE = os.path.join(DATA_DIR, "calendar-cache.json")


def fetch_calendar_via_claude():
    """Next 2 days of timed events, read by Haiku with only the Calendar
    list_events tool loaded. Returns [(start, summary, location)] or None."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import assistant as A
    deny = [f"mcp__claude_ai_{srv}" for srv in ["Gmail", "Notion", "Google_Drive"] + A.MCP_DROP_SERVERS]
    deny += [f"mcp__claude_ai_Google_Calendar__{t}"
             for t in A.MCP_TOOL_NAMES["Google_Calendar"] if t != "list_events"]
    today = dt.date.today()
    prompt = (f"Liste mes événements Google Agenda (agenda principal) du {today} au "
              f"{today + dt.timedelta(days=2)} inclus, fuseau {tz_name()}. Réponds UNIQUEMENT "
              'par un tableau JSON, sans texte autour : [{"start": "AAAA-MM-JJTHH:MM", '
              '"summary": "...", "location": "..."}]. Ignore les événements sur la journée '
              "entière et ceux que j'ai refusés. Tableau vide s'il n'y a rien.")
    cmd = ["claude", "-p", "--output-format", "json", "--model", A.MODELS["fast"],
           "--system-prompt", "Tu extrais des données d'agenda. Un seul appel d'outil.",
           "--disable-slash-commands", "--tools", "",
           "--allowedTools", "mcp__claude_ai_Google_Calendar__list_events",
           "--disallowedTools", *deny, "--no-session-persistence", "--", prompt]
    env = {k: v for k, v in os.environ.items() if k not in A.BILLING_ENV}
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    try:
        r = subprocess.run(cmd, cwd=HOME, env=env, capture_output=True, text=True,
                           timeout=180, stdin=subprocess.DEVNULL)
        res = json.loads(r.stdout)
        if res.get("is_error"):
            return None
        text = res.get("result", "")
        items = json.loads(text[text.index("["):text.rindex("]") + 1])
    except (subprocess.TimeoutExpired, OSError, ValueError):
        return None
    out = []
    for it in items:
        try:
            start = dt.datetime.fromisoformat(it["start"]).replace(tzinfo=TZ)
        except (KeyError, ValueError, TypeError):
            continue
        out.append((start.isoformat(), it.get("summary") or pick("Événement", "Event"), it.get("location") or ""))
    return out


def calendar_events_via_claude(state):
    try:
        with open(CAL_CACHE) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {"fetched": 0, "events": []}
    hour = dt.datetime.now().hour
    stale = time.time() - cache["fetched"] > state["calendar_refresh_hours"] * 3600
    new_day = dt.date.fromtimestamp(cache["fetched"]) != dt.date.today() if cache["fetched"] else True
    if 7 <= hour < 22 and (stale or new_day):
        events = fetch_calendar_via_claude()
        if events is not None:
            cache = {"fetched": time.time(), "events": events}
        else:   # failed (offline…): retry in 30 min, not at every loop
            cache["fetched"] = time.time() - state["calendar_refresh_hours"] * 3600 + 1800
        with open(CAL_CACHE, "w") as f:
            json.dump(cache, f, ensure_ascii=False, indent=1)
    return [(f"{s}:{summary}", dt.datetime.fromisoformat(s), summary, loc)
            for s, summary, loc in cache["events"]]


def check_calendar(state):
    url = state.get("ics_url")
    now = dt.datetime.now(dt.timezone.utc)
    lead = dt.timedelta(minutes=state["remind_minutes"])
    if not url:
        if not state.get("calendar_via_claude", True):
            return
        for uid, start, summary, location in calendar_events_via_claude(state):
            if now <= start <= now + lead:
                mins = max(1, round((start - now).total_seconds() / 60))
                text = "\uf073 " + pick(f"**{summary}** dans {mins} min ({start.strftime('%H:%M')})",
                                         f"**{summary}** in {mins} min ({start.strftime('%H:%M')})")
                if location:
                    text += f", {location}"
                nudge(state, f"cal:{uid}", "calendar", text + ".")
        return
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            ics = r.read().decode("utf-8", "replace")
    except OSError:
        return
    now = dt.datetime.now(dt.timezone.utc)
    lead = dt.timedelta(minutes=state["remind_minutes"])
    for uid, start, summary, location in upcoming_events(ics, now, now + lead):
        mins = max(1, round((start - now).total_seconds() / 60))
        local = start.astimezone(TZ).strftime("%H:%M")
        text = " " + pick(f"**{summary}** dans {mins} min ({local})",
                                  f"**{summary}** in {mins} min ({local})")
        if location:
            text += f", {location}"
        nudge(state, f"cal:{uid}:{start.isoformat()}", "calendar", text + ".")


# ── Morning brief ────────────────────────────────────────────────────────
def todays_events(state):
    """Today's events as [(local start, summary, location)] sorted by time, or
    None when no calendar source is available (no iCal URL, Claude disabled)."""
    day0 = dt.datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    day1 = day0 + dt.timedelta(days=1)
    url = state.get("ics_url")
    if url:
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                ics = r.read().decode("utf-8", "replace")
        except OSError:
            return None
        found = [(s, summ, loc) for _, s, summ, loc in upcoming_events(ics, day0, day1)]
    elif state.get("calendar_via_claude", True):
        found = [(s, summ, loc) for _, s, summ, loc in calendar_events_via_claude(state)]
    else:
        return None
    local = [(s.astimezone(), summ, loc) for s, summ, loc in found]
    return sorted((e for e in local if day0 <= e[0] < day1), key=lambda e: e[0])


def morning_text(name, events, pending):
    """The brief itself. `events` is None when the agenda couldn't be read."""
    hello = pick("Bonjour", "Good morning") + (f" {name}" if name else "")
    out = ["\uf185 " + pick(f"**{hello}** — voici ta journée :", f"**{hello}** — here is your day:")]
    if events is not None:
        out.append("")
        if events:
            out.append("**Agenda**")
            for start, summary, location in events:
                out.append(f"- {start.strftime('%H:%M')} {summary}" + (f" ({location})" if location else ""))
        else:
            out.append(pick("Rien au programme dans ton agenda.", "Nothing on your calendar today."))
    if pending:
        out += ["", pick("**À finir côté git**", "**To wrap up on git**")] + pending
    return "\n".join(out)


def check_morning(state):
    hour = state.get("morning_hour")
    if not isinstance(hour, int) or isinstance(hour, bool) or not 0 <= hour <= 23:
        return                                   # disabled
    now = dt.datetime.now()
    # From the set hour for 5 hours: a brief at 3 pm would be silly.
    if not hour <= now.hour < hour + 5:
        return
    key = f"morning:{now.date()}"
    if key in state["seen"]:
        return
    nudge(state, key, "morning",
          morning_text(user_name(), todays_events(state), unpushed_lines(state)))


# ── Iris updates ─────────────────────────────────────────────────────────
def source_repo():
    """The git clone Iris was installed from (written by install.sh), or None."""
    try:
        with open(os.path.join(DATA_DIR, "source")) as f:
            repo = f.read().strip()
    except OSError:
        return None
    return repo if os.path.isdir(os.path.join(repo, ".git")) else None


def check_updates(state):
    repo = source_repo()
    if not repo or not state.get("check_updates", True):
        return
    if run(["git", "fetch", "--quiet"], cwd=repo, timeout=60)[0]:
        return
    code, behind = run(["git", "rev-list", "--count", "HEAD..@{u}"], cwd=repo)
    if code or not behind.isdigit():
        return                                   # unknown: leave the flag alone
    flag = os.path.join(DATA_DIR, "update-available")     # read by the panel's Update button
    n = int(behind)
    # The clone can also be ahead of what is installed (pulled by hand, or the
    # push came from this very clone): that is an update to install too.
    try:
        with open(os.path.join(DATA_DIR, "installed-rev")) as f:
            installed = f.read().strip()
    except OSError:
        installed = ""
    _, head = run(["git", "rev-parse", "HEAD"], cwd=repo)
    if installed and installed != head:
        code, local = run(["git", "rev-list", "--count", f"{installed}..HEAD"], cwd=repo)
        n += int(local) if code == 0 and local.isdigit() else 1
    if n == 0:
        try:
            os.remove(flag)
        except OSError:
            pass
        return
    _, latest = run(["git", "rev-parse", "@{u}" if int(behind) else "HEAD"], cwd=repo)
    with open(flag, "w") as f:
        f.write(str(n))
    nudge(state, f"update:{latest}", "update",
          "\uf019 " + pick(
              f"**Mise à jour d'Iris disponible** ({n} nouveauté{'s' if n > 1 else ''}). "
              "Dis-moi « mets-toi à jour » et je m'en occupe.",
              f"**Iris update available** ({n} new change{'s' if n > 1 else ''}). "
              "Tell me “update yourself” and I'll take care of it."),
          {"id": "update", "label": pick("Mettre à jour", "Update now")})


# ── PC health ────────────────────────────────────────────────────────────
def check_health(state):
    today = dt.date.today()
    for mount in ("/", HOME):
        try:
            u = shutil.disk_usage(mount)
        except OSError:
            continue
        pct = u.used / u.total * 100
        if pct > 90:
            nudge(state, f"disk:{mount}:{today}", "health",
                  f" " + pick(
                      f"**Disque presque plein** : `{short(mount) or '/'}` est à "
                      f"{pct:.0f} % ({u.free / 1e9:.1f} Go libres). Demande-moi de trouver ce qui prend de la place.",
                      f"**Disk almost full**: `{short(mount) or '/'}` is at "
                      f"{pct:.0f}% ({u.free / 1e9:.1f} GB free). Ask me to find what takes the space."))

    bat = "/sys/class/power_supply/BAT0"
    try:
        cap = int(open(f"{bat}/capacity").read())
        status = open(f"{bat}/status").read().strip()
        if status == "Discharging" and cap <= 15:
            # One alert per discharge (reset once it charges again).
            if "battery:low" not in state["seen"]:
                nudge(state, "battery:low", "health",
                      f" " + pick(f"**Batterie à {cap} %**, branche ton chargeur.",
                                  f"**Battery at {cap}%**, plug in your charger."))
        elif status != "Discharging":
            state["seen"].pop("battery:low", None)
    except (OSError, ValueError):
        pass

    for scope in ([], ["--user"]):
        _, out = run(["systemctl", *scope, "--failed", "--no-legend", "--plain"], timeout=10)
        for line in out.splitlines():
            unit = line.split()[0] if line.split() else ""
            if unit:
                nudge(state, f"failed:{unit}:{today}", "health",
                      f" " + pick(f"**Service en échec** : `{unit}`. Demande-moi de regarder ce qui cloche.",
                                  f"**Service failed**: `{unit}`. Ask me to look into it."))

    week = today.isocalendar()[:2]
    key = f"updates:{week[0]}-{week[1]}"
    if key not in state["seen"] and shutil.which("checkupdates"):
        _, out = run(["checkupdates"], timeout=120)
        n = len(out.splitlines()) if out else 0
        if n >= 80:
            nudge(state, key, "health",
                  f" " + pick(f"**{n} mises à jour en attente**. Lance `sudo pacman -Syu` quand tu as 5 minutes.",
                                  f"**{n} updates pending**. Run `sudo pacman -Syu` when you have 5 minutes."))


# ── Main loop ────────────────────────────────────────────────────────────
CHECKS = {                      # name → (function, interval in seconds)
    "calendar":     (check_calendar, 300),
    "git_behind":   (check_git_behind, 600),
    "git_unpushed": (check_git_unpushed, 900),
    "morning":      (check_morning, 600),
    "updates":      (check_updates, 6 * 3600),
    "health":       (check_health, 900),
}


def main():
    os.makedirs(DATA_DIR, mode=0o700, exist_ok=True)
    if len(sys.argv) == 3 and sys.argv[1] == "--once":
        state = load()
        CHECKS[sys.argv[2]][0](state)
        save(state)
        return
    last = {name: 0.0 for name in CHECKS}
    time.sleep(45)              # let the session settle after login
    while True:
        state = load()          # re-read: the config may have been edited
        for name, (fn, every) in CHECKS.items():
            if time.time() - last[name] >= every:
                last[name] = time.time()
                try:
                    fn(state)
                except Exception as e:   # one broken check must not stop the rest
                    sys.stderr.write(f"[iris-watch] {name}: {e}\n")
        save(state)
        time.sleep(30)


if __name__ == "__main__":
    main()
