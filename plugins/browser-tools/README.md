# browser-tools

Two browser tools for Claude Code on macOS, set up by one installer.

- **Jev Ultrafast** ([browser-use/jev-ultrafast](https://github.com/browser-use/jev-ultrafast)): a browser agent that
  clicks and types through a public site to reach a goal. Runs in its own headless Chrome, so no window pops up and
  none of your logins are exposed. Typical task: 3 to 10 seconds.
- **Agent Reach** ([Panniantong/Agent-Reach](https://github.com/Panniantong/Agent-Reach)): read-only search and
  reading for Reddit, YouTube transcripts, X, GitHub, LinkedIn jobs and more. Installs its own `agent-reach` skill.

## Why this instead of installing Jev and Agent Reach yourself

Same tools, pinned to the versions tested below. The difference is what happens around them. Each fix here is a
problem we hit setting up the standard versions on 2026-11-21.

| Standard setup | With this plugin |
|---|---|
| Jev attaches to your everyday Chrome through Browser Harness, so the agent can use every site you are signed into. On macOS the attach failed outright (`DevToolsActivePort: Operation not permitted`). | Jev gets its own headless Chrome with an empty profile. None of your logins are exposed, and the macOS block does not apply. |
| The Chrome window jumps in front of whatever you are working on. | Headless: no window, no focus stealing. |
| The example config's text model (`inception/mercury-2.5`) is no longer on OpenRouter, so every typing step fails with HTTP 404. | Uses `anthropic/claude-haiku-5.5`, which is live, and you can switch it with `JEV_TEXT_MODEL`. |
| A stuck task runs forever. | Stopped after 60 s (`JEV_TIMEOUT`), whole process group killed, no leftovers. |
| Each tool is installed separately from its latest build, which can change under you. | One installer, safe to re-run, with Jev and Agent Reach pinned to tested versions. |
| Claude does not know when to use which tool. | The `jev` skill tells Claude to use Jev for clicking through public sites, Agent Reach or WebFetch for reading, and your own browser for anything that needs a login. It also says never to pay, send, post or delete, and to check that a "done" task really reached the goal. |
| Keys sit in `.env`, and nothing stops an agent from printing them. | The skill forbids reading the key file and checks keys without showing them. |

None of this makes Jev itself faster. A typical task still takes 3 to 10 seconds.

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
