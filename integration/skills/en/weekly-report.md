---
description: Summarise my git activity of the week across my projects ("weekly report", "what did I do this week")
---
1. Find my repositories: `ls -d ~/*/.git ~/*/*/.git` (if my projects live elsewhere, check your memory or ask me where).
2. For each repository, list my commits from the last 7 days: `git -C <repo> log --since="7 days ago" --oneline`. Skip repositories with no recent commit.
3. Answer with a short list per project (2 to 4 bullets: what changed and why), then a one-sentence summary. No tables.
