---
name: jev
description: >
  Fast headless browser agent (Jev Ultrafast, browser-use x TypeSafe) that clicks, types and navigates a website
  to reach a goal, with no window on screen. Use when the user says "use jev", "ultrafast", or wants a quick
  public-web task done by clicking through a site (search, filters, open an article, fill a public search form)
  and does not need their own logins. Also use when the user asks to install, set up or check Jev or Agent Reach.
  Not for sites needing the user's sign-in, uploads, iframes or canvas apps, or long multi-step jobs: use the
  user's own logged-in browser tool for those. For reading a post, transcript or page text,
  use the agent-reach skill or a web fetch tool instead. Never use for payments, sending, posting or deleting.
---

# Jev Ultrafast

Where each agent gets this skill: Claude Code from the browser-tools plugin; Codex and Kimi Code from
`~/.agents/skills/jev` (put there by `install.sh`).

Runs Jev against an isolated headless Chrome (a port from 9333 to 9340, its own empty profile at
`~/tools/jev-chrome-profile-<port>`), so no window opens and none of the user's logins are exposed. Works on macOS
(fully tested) and Linux (install and headless Chrome start checked in CI; a full task not yet run on Linux). Up to
8 tasks can run at the same time, each on its own port.

## First use and upgrades: install

Run the installer that sits next to this file when the launcher is missing or older than this skill, that is
when this check fails:

```bash
grep -q '^JEV_RUN_VERSION=1.2.0$' ~/tools/jev-ultrafast/jev-run.sh
```

```bash
bash "<this skill's directory>/install.sh"
```

It installs Agent Reach (pinned) and its skill, Jev Ultrafast (pinned) at `~/tools/jev-ultrafast`, the
launcher, and a copy of this skill in `~/.agents/skills/jev`. It needs `git`, `uv` and Google Chrome or Chromium, and is safe to re-run. It ends by saying whether API keys are
missing. If they are, tell the user to add their own keys (you never type or read them):

```bash
open -e ~/tools/jev-ultrafast/.env   # macOS; on Linux use any editor
```

- `TYPESAFE_API_KEY`: from https://docs.typesafe.ai
- `TEXT_MODEL_API_KEY`: an OpenRouter key (https://openrouter.ai/keys)

To check keys without seeing them:
`grep -E '^(TYPESAFE_API_KEY|TEXT_MODEL_API_KEY)=.+' ~/tools/jev-ultrafast/.env | sed -E 's/=.*/=<set>/'`

## Run a task

```bash
~/tools/jev-ultrafast/jev-run.sh "<start url>" "<one clear goal>"
```

- Runs in the foreground; a task takes about 3 to 10 seconds and is stopped after 60 s (`JEV_TIMEOUT` to change,
  a whole number of seconds from 1 to 3600). It prints one line per step, the last one ending in `done` or
  `blocked`, then the final URL.
- Exit 0 only means the run finished: read the final status line (`done` or `blocked`) and the URL. Exit 1 means
  Chrome or Jev failed (the launcher says why). Exit 124 means it hit the time limit. Exit 75 means all 8 slots
  are busy: wait and retry. Exit 2 means bad arguments or a bad `JEV_TIMEOUT`. Exit 127 means a command was not
  found. Exit 129, 130 or 143 means it was hung up, interrupted or stopped; other codes above 128 mean it was
  killed by signal (code minus 128).
- Parallel tasks are fine: start several `jev-run.sh` calls at once and each gets its own slot.
- `JEV_FRESH=1` restarts that slot's Chrome with an empty profile (use it when a site remembers state from an
  earlier run).
- Write the goal as an outcome with a stop condition, e.g. "Find flights Zurich to London on 20 Sept 2026, stop
  when results are visible."
- Always check the final status line and URL against the goal. A `done` state is not proof the goal was met.

## Rules

- Public pages only. Never enter passwords, card numbers or personal data. Never submit forms that send, buy,
  post or delete.
- Never read, print or commit `~/tools/jev-ultrafast/.env`; it holds the API keys.
- HTTP 404 from the model provider means the text model name is stale. Run with
  `JEV_TEXT_MODEL=<another OpenRouter model id>` (default `anthropic/claude-haiku-5.5`).
- Cannot connect: headless Chrome is down; the launcher restarts it.
- Stop every Jev headless Chrome and helper with `~/tools/jev-ultrafast/jev-run.sh --stop` (it prints what it
  stopped). Fallback if the launcher is missing: `pkill -U "$(id -u)" -f '[j]ev-chrome-profile'` (Chrome only).
- Unsupported: shadow roots, frames, canvas, file uploads, pop-up tabs.
