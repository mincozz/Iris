# Iris

[![CI](https://github.com/mincozz/IRIS/actions/workflows/ci.yml/badge.svg)](https://github.com/mincozz/IRIS/actions/workflows/ci.yml)

[Français](README.md) · English

A pixel-art personal assistant that lives in the bar of a [Quickshell](https://quickshell.org) shell (Wayland). It drives the [Claude Code](https://claude.com/claude-code) CLI on **your** Claude account: every user uses their own subscription, nothing goes through a project server.

> Independent project, not affiliated with Anthropic. "Claude" is a trademark of Anthropic.

## What it does

- **Chat** in a bar panel, with access to your PC (files, read-only commands, system info) and, if you enabled the Claude connectors, your calendar, mail, Notion and Drive.
- **Clear permissions**: reading is free, anything that changes something asks for a click on Allow / Deny.
- **Unprompted alerts**, no quota: `git pull` to do (with a button), unpushed work, calendar reminders, disk, battery, failed services, updates, plus a **morning brief**.
- **Shortcuts**: `SUPER + I` sends your selection to Iris, `SUPER + SHIFT + I` attaches it so you type an instruction.
- Undoable **folder tidying**, **skills** (your own Markdown recipes), local **memory**, **French and English**.
- **One-click update** (⬇ button) and a **diagnostic** (`iris-doctor`).

## Requirements

- Linux with a Wayland compositor and [Quickshell](https://quickshell.org); Hyprland is recommended (blur, shortcuts) but optional.
- Python 3.9+, `git`, and the `claude` CLI **logged in** to a Claude account (run `claude` once to sign in).
- Optional: `wl-clipboard` (shortcut), `libnotify` (notifications), `glib2`/`gio` (trash for tidying), a file manager (Nautilus, otherwise `xdg-open`).
- Your Quickshell shell must provide a `theme` object (see "Contract with the host shell" in [AGENTS.md](AGENTS.md), in French); `test/shell.qml` is a minimal one.

## Install

```bash
git clone git@github.com:mincozz/IRIS.git && cd IRIS
./install.sh --dry-run   # see what will be done
./install.sh             # install
```

Options: `--prefix DIR` (another Quickshell folder), `--no-hypr`, `-y` (no questions), `--uninstall`, `--language fr|en|auto`, `--name NAME`, `--deny-read "~/.ssh,~/.gnupg"`, `--fast-model ID`, `--power-model ID`, `--ask-key` / `--ask-edit-key`, `--reconfigure`.

The installer checks the requirements, copies the files, creates `~/.local/share/qs-assistant/` (empty memory, `watch.json`, `config.json`, example skills; never overwritten), wires `shell.qml` (marked block, `.iris-bak` backup), adds the Hyprland blur rule and the two shortcuts, and runs the diagnostic. It is safe to re-run. Two optional steps stay manual because they depend on your shell: the avatar button in the bar (`integration/Bar.qml.snippet`) and click-to-open on an alert (`integration/NotificationToast.qml.snippet`).

Check: `qs ipc call assistant toggle|open|close|ask "…"`. Diagnostic: `~/.config/quickshell/scripts/iris-doctor`.

An AI assistant can do the install for you: [AGENTS.md](AGENTS.md) (read via `CLAUDE.md` by Claude Code) describes the procedure.

## Update

`scripts/iris-update` (or the ⬇ button in the panel, or "update yourself" to Iris) does a `git pull --ff-only` in your clone when the remote moved, or reinstalls when your clone is newer than the installed version, keeping your config. Iris checks every 6 hours and shows an alert with an **Update now** button (`"check_updates": false` in `watch.json` to disable). Keep the clone in place.

## Configuration

`~/.local/share/qs-assistant/config.json` (all keys optional, invalid values are ignored with a message on stderr):

| Key | Purpose |
|---|---|
| `language` | `fr` (default), `en` or `auto` (follows `$LANG`). `IRIS_LANG=en` overrides the file |
| `user_name` | What Iris calls you |
| `models` | `fast` and `power` model ids (default Haiku / Sonnet) |
| `session_idle_minutes` | Idle time before a fresh conversation (default 30) |
| `prompt_file` | Path to your own prompt instead of the built-in one |
| `deny_read_paths` | Folders `Read`/`Grep`/`Glob` and `cat`/`head`/`tail`/`less`/`grep` can't read, e.g. `["~/.ssh"]`. Best effort, not a sandbox |
| `extra_readonly_commands` | Commands run without asking: make sure they have no side effects |
| `extra_denied_commands` | Commands refused even with a click |

Alerts and the morning brief are set in `watch.json` (`morning_hour`, `calendar_via_claude`, `ics_url`, `timezone`, `check_updates`, `remind_minutes`, `unpushed_hour`, `repo_roots`, `exclude`; example in `integration/watch.example.json`). `python3 scripts/iris-watch.py --once morning` tests the brief.

## Skills

Markdown recipes in `~/.local/share/qs-assistant/skills/name.md`, with an optional front matter line `description:`. Iris gets the list and reads a recipe when your request matches it, or when you type `/name`. Plain file names, 30 recipes max. Examples are copied at install time in your language. Recipes are your instructions and get no extra permissions.

## Security in brief

Iris runs `claude` with your rights. Reading files and read-only commands need no confirmation; everything else goes through Allow / Deny, showing what would be written. `sudo`, `su`, `dd`, `mkfs` and relatives are refused. The content of mails, pages and files is treated as data, not orders. History, memory and calendar stay in `~/.local/share/qs-assistant/` (mode 700). Details and how to report a vulnerability: [SECURITY.md](SECURITY.md) (French).

## Known limits

- Built and tested on Arch Linux + Hyprland + Quickshell; elsewhere the installer and `iris-doctor` tell you what is missing, but the bar button, blur and shortcuts need adapting.
- Every message uses your Claude subscription quota; the fast model is the default, the powerful one is used for code.
- Calendar, mail, Notion and Drive come through your Claude account's connectors; without them Iris can't see them (the calendar can also come from an iCal address, `ics_url`).
- As with any assistant that reads external content, prompt injection remains possible: keep an eye on the permission cards.

## License

[MIT](LICENSE). Contributions are accepted under the same license.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `test/test-e2e.sh --no-gui` before a pull request.
