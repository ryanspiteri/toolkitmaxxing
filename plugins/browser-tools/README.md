# browser-tools

Two browser tools for Claude Code, Codex and Kimi Code on macOS (fully tested) and Linux (install and headless Chrome
start checked in CI; a full task not yet run on Linux), set up by one installer.

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
| Jev attaches to your everyday Chrome through Browser Harness, so the agent can use every site you are signed into. On macOS the attach failed outright (`DevToolsActivePort: Operation not permitted`). | Jev gets its own headless Chrome with an empty profile, and its own Browser Harness home (`~/tools/jev-ultrafast/.harness`), so it never reuses a Browser Harness helper of yours that is attached to your everyday Chrome. None of your logins are exposed, and the macOS block does not apply. |
| The Chrome window jumps in front of whatever you are working on. | Headless: no window, no focus stealing. |
| The example config's text model (`inception/mercury-2.5`) is no longer on OpenRouter, so every typing step fails with HTTP 404. | Uses `anthropic/claude-haiku-5.5`, which is live, and you can switch it with `JEV_TEXT_MODEL`. |
| A stuck task runs forever. | Stopped after 60 s (`JEV_TIMEOUT`), the task's whole process group killed, and the task also dies if the launcher itself is killed. The headless Chrome and its Browser Harness helper stay up for the next task until `jev-run.sh --stop`. |
| Each tool is installed separately from its latest build, which can change under you. | One installer, safe to re-run. Jev and Agent Reach are pinned; their own dependencies follow their lock files. |
| Claude does not know when to use which tool. | The `jev` skill tells Claude to use Jev for clicking through public sites, Agent Reach or WebFetch for reading, and your own browser for anything that needs a login. It also says never to pay, send, post or delete, and to check that a "done" task really reached the goal. |
| Keys sit in `.env`, and nothing stops an agent from printing them. | The skill forbids reading the key file and checks keys without showing them. |

None of this makes Jev itself faster. A typical task still takes 3 to 10 seconds.

## Setup

1. Install the plugin (see the repo README).
2. In Claude Code, say "set up jev". Claude runs `skills/jev/install.sh` (pinned versions, safe to re-run).
3. Add your own keys by editing `~/tools/jev-ultrafast/.env` (`open -e` on macOS, any editor on Linux). The
   installer makes that file readable only by you.
   - `TYPESAFE_API_KEY` from [TypeSafe](https://docs.typesafe.ai)
   - `TEXT_MODEL_API_KEY` from [OpenRouter](https://openrouter.ai/keys) (types text with `anthropic/claude-haiku-5.5`)
4. Try it: "use jev to open the Wikipedia article on Alan Turing".

You can also run tasks yourself:

```bash
~/tools/jev-ultrafast/jev-run.sh https://en.wikipedia.org/wiki/Main_Page "Open the article on Alan Turing"
```

## Other agents (Codex, Kimi Code)

The installer puts the `jev` skill in `~/.agents/skills` (and Agent Reach puts its own skill there too):

- Codex: confirmed: Codex lists jev in its skills (`codex debug prompt-input`).
- Kimi Code: reads `~/.agents/skills` (per Kimi Code's own built-in docs); not yet tried in a live Kimi session.

```bash
git clone https://github.com/ryanspiteri/toolkitmaxxing ~/tools/toolkitmaxxing
bash ~/tools/toolkitmaxxing/plugins/browser-tools/skills/jev/install.sh
```

Then restart Codex or Kimi Code (start a new session) to load the skill, add your keys as in Setup step 3, and ask
it to "use jev". To update: `git -C ~/tools/toolkitmaxxing pull`, then run the installer again.

Agent Reach is installed from a copy of its pinned release kept at `~/tools/agent-reach/agent-reach-<version>.zip`,
checked against the sha256 in `install.sh` before it is installed. To move to a new Agent Reach version, bump
`AGENT_REACH_URL` and `AGENT_REACH_SHA256` in `install.sh` (after testing it) and run the installer again.
Set `AGENTS_SKILLS_DIR` if your agent reads skills from another folder. It moves only the jev copy; Agent Reach
always puts its own skill in `~/.agents/skills`.

## Settings

Set these as environment variables on the command line, for example `JEV_FRESH=1 ~/tools/jev-ultrafast/jev-run.sh ...`.

- `JEV_TIMEOUT` (default 60): seconds before a task is stopped (exit 124). A whole number from 1 to 3600;
  anything else exits 2.
- `JEV_TEXT_MODEL` (default `anthropic/claude-haiku-5.5`): OpenRouter model that writes typed text.
- `JEV_TEXT_MODEL_BASE_URL`: API base URL for that model. Default `https://openrouter.ai/api/v1`, unless your `.env`
  has a `TEXT_MODEL_BASE_URL` line (or `TEXT_MODEL_BASE_URL` is set in the environment), which is then used.
- `JEV_FRESH=1`: restart the headless Chrome for this run with an empty profile (clears cookies and storage).
- `JEV_CHROME`: path to the Chrome or Chromium binary. Default: Google Chrome on macOS, otherwise the first of
  `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser` on your PATH.
- `JEV_CHROME_ARGS`: extra Chrome flags, for example `--no-sandbox` when running as root or in a container.
- `JEV_HARNESS_HOME` (default `~/tools/jev-ultrafast/.harness`): where Browser Harness keeps Jev's files. Only
  needed when your home folder path is so long that its sockets would not fit (the launcher tells you); set it to
  a short folder, and set it for `--stop` too.

To keep settings without typing them each time, put them in `~/tools/jev-ultrafast/launcher.env`, one `KEY=VALUE`
per line with no quotes, for example `JEV_CHROME_ARGS=--no-sandbox`. Only `JEV_CHROME`, `JEV_CHROME_ARGS`,
`JEV_TEXT_MODEL`, `JEV_TEXT_MODEL_BASE_URL` and `JEV_TIMEOUT` are read from it (as plain text, never run as a script), and a variable set on
the command line wins over the file. If you run the installer with `JEV_CHROME` or `JEV_CHROME_ARGS` set, it writes
them there for you (only when the file does not exist yet).

Exit codes: 0 the run finished (read the last status line: `done` or `blocked`, and check the URL), 1 Chrome or
Jev failed, 2 usage or a bad `JEV_TIMEOUT`, 75 all slots busy, 124 timed out, 127 a command was not found, 129 hung
up (SIGHUP), 130 interrupted (Ctrl-C, SIGINT), 143 stopped (SIGTERM), and any other 128+N killed by signal N.

Parallel runs: up to 8 tasks at once. Each takes a free port from 9333 to 9340 and has its own headless Chrome,
profile (`~/tools/jev-chrome-profile-<port>`) and Browser Harness helper (named `jev-<port>`). With all 8 busy, the
launcher prints `all 8 Jev slots busy` and exits 75. Each slot is held with a kernel file lock
(`~/tools/.jev-locks/<port>.lock`), which the system releases when the run ends, however it ends, so a crashed run
never blocks a slot. If the launcher is killed outright (`kill -9`, a closed terminal, its caller's process group
killed), its task is stopped too. The launcher only attaches to its own Chrome for a port: if something else
answers there, it prints `port <port> is answered by something that is not Jev's Chrome; not attaching` and exits 1.

Browser Harness keeps Jev's sockets, logs and settings in `~/tools/jev-ultrafast/.harness`, never in your own
`~/.config/browser-harness`, and its telemetry is switched off (`BH_TELEMETRY=0`).

Stop every background headless Chrome and Browser Harness helper:

```bash
~/tools/jev-ultrafast/jev-run.sh --stop
```

It prints what it stopped and does not need a free slot. Fallback if the launcher is missing:
`pkill -U "$(id -u)" -f '[j]ev-chrome-profile'` (stops the Chromes only).

## Limits

Known edge cases: Jev decides a port's Chrome is its own by the profile folder name. So if another program grabs a
port while a stuck Jev Chrome is still running, or you run Jev from two home folders as the same user, it can treat
the other one as its own. Neither happens in a normal setup; `jev-run.sh --stop` clears both.

Public pages only. Jev does not handle shadow roots, frames, canvas, file uploads or pop-up tabs, and its `done`
state should be checked against the goal. Never use it to pay, send, post or delete.

The headless Chromes' debugging ports (9333 to 9340) listen on 127.0.0.1 only, but they are shared by every user of
the machine: on a shared computer another local user could connect to them. Up to 8 headless Chromes and their
helpers may stay running in the background until you stop them with `jev-run.sh --stop`.

## Tested

2026-11-21, version 1.0.0, on macOS (Chrome 158): fresh install, Wikipedia tasks in 2.8 to 4.9 s, 60 s kill switch.
Versions: Jev `cf3c406`, Agent Reach v1.6.1.

2026-11-21, version 1.2.0, on macOS 27 (Chrome 158.0.8127.37, /bin/bash 3.2):

- Two tasks at the same time (Alan Turing on port 9333, Ada Lovelace on 9334), both `done` on the right article in
  about 3.5 s, each through its own Browser Harness helper.
- With a Browser Harness "default" helper of the normal kind running (in `~/.config/browser-harness`, attached to
  another Chrome), a Jev run did not use it and left `~/.config/browser-harness` unchanged; `--stop` left it running.
- `JEV_FRESH=1`: new Chrome, profile wiped, task `done`.
- `JEV_TIMEOUT=1` exits 124; SIGTERM exits 143, SIGINT 130, SIGHUP 129. Each time no task process was left, Chrome
  stayed up and the next run got port 9333.
- `kill -9` of a running launcher, and killing its caller's whole process group: the task was gone within 0.2 s and
  the next run got port 9333.
- Exit 75 with all 8 slots held; `--stop` still worked with all 8 held. Bad `JEV_TIMEOUT` values (`abc`, `0`,
  `3601`, `1.5`, `-5`) exit 2, from the command line or `launcher.env`.
- `launcher.env` values used, unknown keys ignored, command-line values winning over the file.
- The installer stopping a 1.0.0-style Chrome on the unsuffixed profile while leaving the per-port Chromes running.
- An install into an empty home directory with no `~/.claude`: the Agent Reach zip was kept in `~/tools/agent-reach`
  and passed its sha256 check; a second install reused it after checking it again; a corrupted copy was downloaded
  again; an older Agent Reach was replaced by the pinned one; `uv tool upgrade agent-reach` still worked; a wrong
  pinned sha256 stopped the install.
- A fake DevTools responder on 127.0.0.1:9333: exit 1, `not Jev's Chrome; not attaching`, no Chrome started and
  no task run. A plain web server on 127.0.0.1:9333: Chrome could not take the port, exit 1, and the Chrome it
  launched was stopped. Jev's own Chrome frozen (port not answering): stopped and replaced, task `done`.
- `uv` missing: exit 1 with `uv not found; run the installer` before any Chrome starts. A Browser Harness socket
  path over 100 bytes: exit 1 with a clear message. A lock file that cannot be locked: exit 1 with the error, not
  "slots busy".
- The text model base URL: taken from `.env` when it has a `TEXT_MODEL_BASE_URL` line, from `JEV_TEXT_MODEL_BASE_URL`
  (command line or `launcher.env`) when set, otherwise OpenRouter. A URL starting with `-` reaches Jev.
- `~/.agents/skills/jev/jev-run.sh` run directly from another folder: task `done`. The installer sets `.env` to
  mode 600 and re-runs Agent Reach's setup when it installs a different Agent Reach version.
- Codex lists the `jev` skill.

Kimi Code has not been tried in a live session. Linux: install and headless Chrome start are checked in CI; a full
task has not been run on Linux.
