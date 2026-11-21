---
name: jev
description: >
  Fast headless browser agent (Jev Ultrafast, browser-use x TypeSafe) that clicks, types and navigates a website
  to reach a goal, with no window on screen. Use when the user says "use jev", "ultrafast", or wants a quick
  public-web task done by clicking through a site (search, filters, open an article, fill a public search form)
  and does not need their own logins. Also use when the user asks to install, set up or check Jev or Agent Reach.
  Not for sites needing the user's sign-in, uploads, iframes or canvas apps, or long multi-step jobs: use the
  user's own browser tools (for example Claude in Chrome) for those. For reading a post, transcript or page text,
  use the agent-reach skill or WebFetch instead. Never use for payments, sending, posting or deleting.
---

# Jev Ultrafast

Runs Jev against an isolated headless Chrome (port 9333, its own empty profile at `~/tools/jev-chrome-profile`),
so no window opens and none of the user's logins are exposed. macOS only.

## First use: install

If `~/tools/jev-ultrafast/jev-run.sh` does not exist, run the installer that sits next to this file:

```bash
bash "<this skill's directory>/install.sh"
```

It installs Agent Reach (pinned) and its skill, Jev Ultrafast (pinned) at `~/tools/jev-ultrafast`, and the
launcher. It needs `git`, `uv` and Google Chrome, and is safe to re-run. It ends by saying whether API keys are
missing. If they are, tell the user to add their own keys (you never type or read them):

```bash
open -e ~/tools/jev-ultrafast/.env
```

- `TYPESAFE_API_KEY`: from https://docs.typesafe.ai
- `TEXT_MODEL_API_KEY`: an OpenRouter key (https://openrouter.ai/keys)

To check keys without seeing them:
`grep -E '^(TYPESAFE_API_KEY|TEXT_MODEL_API_KEY)=.+' ~/tools/jev-ultrafast/.env | sed -E 's/=.*/=<set>/'`

## Run a task

```bash
~/tools/jev-ultrafast/jev-run.sh "<start url>" "<one clear goal>"
```

- Runs in the foreground; a task takes about 3 to 10 seconds and is stopped after 60 s (`JEV_TIMEOUT` to change).
  It prints one line per step and the final URL when the state is `done`. Exit 124 means it hit the time limit.
- Write the goal as an outcome with a stop condition, e.g. "Find flights Zurich to London on 20 Sept 2026, stop
  when results are visible."
- Always check the final URL or page against the goal. A `done` state is not proof the goal was met.

## Rules

- Public pages only. Never enter passwords, card numbers or personal data. Never submit forms that send, buy,
  post or delete.
- Never read, print or commit `~/tools/jev-ultrafast/.env`; it holds the API keys.
- HTTP 404 from the model provider means the text model name is stale. Run with
  `JEV_TEXT_MODEL=<another OpenRouter model id>` (default `anthropic/claude-haiku-5.5`).
- Cannot connect: headless Chrome is down; the launcher restarts it. Stop it with `pkill -f jev-chrome-profile`.
- Unsupported: shadow roots, frames, canvas, file uploads, pop-up tabs.
