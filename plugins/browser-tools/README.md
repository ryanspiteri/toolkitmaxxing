# browser-tools

Two browser tools for Claude Code on macOS, set up by one installer.

- **Jev Ultrafast** ([browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast)): a browser agent that
  clicks and types through a public site to reach a goal. Runs in its own headless Chrome, so no window pops up and
  none of your logins are exposed. Typical task: 3 to 10 seconds.
- **Agent Reach** ([Panniantong/Agent-Reach](https://github.com/Panniantong/Agent-Reach)): read-only search and
  reading for Reddit, YouTube transcripts, X, GitHub, LinkedIn jobs and more. Installs its own `agent-reach` skill.

## Setup

1. Install the plugin (see the repo README).
2. In Claude Code, say "set up jev". Claude runs `skills/jev/install.sh` (pinned versions, safe to re-run).
3. Add your own keys: `open -e ~/tools/jev-ultrafast/.env`
   - `TYPESAFE_API_KEY` from [TypeSafe](https://docs.typesafe.ai)
   - `TEXT_MODEL_API_KEY` from [OpenRouter](https://openrouter.ai/keys) (types text with `anthropic/claude-haiku-5.5`)
4. Try it: "use jev to open the Wikipedia article on Alan Turing".

You can also run tasks yourself:

```bash
~/tools/jev-ultrafast/jev-run.sh https://en.wikipedia.org/wiki/Main_Page "Open the article on Alan Turing"
```

## Settings

- `JEV_TIMEOUT` (default 60): seconds before a task is stopped (exit 124).
- `JEV_TEXT_MODEL` (default `anthropic/claude-haiku-5.5`): OpenRouter model that writes typed text.
- Stop the background headless Chrome: `pkill -f jev-chrome-profile`

## Limits

Public pages only. Jev does not handle shadow roots, frames, canvas, file uploads or pop-up tabs, and its `done`
state should be checked against the goal. Never use it to pay, send, post or delete.

## Tested

2026-11-21 on macOS (Chrome 158): fresh install, Wikipedia tasks in 2.8 to 4.9 s, 60 s kill switch, no leftover
processes. Versions: Jev `cf3c406`, Agent Reach v1.6.1.
