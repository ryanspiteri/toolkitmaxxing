# toolkitmaxxing

Small, tested tools and skills for [Claude Code](https://claude.com/claude-code), Codex and Kimi Code, shared as a Claude Code plugin marketplace.

## Install

In your terminal:

```bash
claude plugin marketplace add ryanspiteri/toolkitmaxxing
claude plugin install browser-tools@toolkitmaxxing
```

Or inside Claude Code: `/plugin marketplace add ryanspiteri/toolkitmaxxing`, then `/plugin` to browse.

Get updates later with `claude plugin marketplace update toolkitmaxxing`.

## Other agents (Codex, Kimi Code)

The installer puts the `jev` skill in `~/.agents/skills`. Codex: confirmed: Codex lists jev in its skills
(`codex debug prompt-input`). Kimi Code: reads `~/.agents/skills` (per Kimi Code's own built-in docs); not yet tried
in a live Kimi session.

```bash
git clone https://github.com/ryanspiteri/toolkitmaxxing ~/tools/toolkitmaxxing
bash ~/tools/toolkitmaxxing/plugins/browser-tools/skills/jev/install.sh
```

Then restart Codex or Kimi Code (start a new session) to load the skill. To update:
`git -C ~/tools/toolkitmaxxing pull`, then run the installer again.

## Tools

| Plugin | What it does | Needs |
|---|---|---|
| [browser-tools](plugins/browser-tools/) | `jev` skill: a headless browser agent that clicks through public sites in about 3 to 10 seconds, with no window. Installs [Agent Reach](https://github.com/Panniantong/Agent-Reach) too, for read-only access to Reddit, YouTube transcripts, X, GitHub and more. | Claude Code, Codex or Kimi Code; macOS (fully tested) or Linux (install and headless Chrome start checked in CI; a full task not yet run on Linux); git, uv, Chrome or Chromium; your own TypeSafe and OpenRouter keys |

## Rules for adding a tool

- One folder per plugin under `plugins/`, with `.claude-plugin/plugin.json`, its skills, and a README.
- No keys, tokens, personal paths or private business details, ever. Each person brings their own keys.
- Third-party code is installed from its own repo at a pinned version, never copied in.
- Test it on a real machine before it goes in, and say in its README what was tested and when.
- Run `claude plugin validate .` before pushing.
- Bump `version` in the plugin's `plugin.json` on every change, or friends won't get the update. CI enforces it.
- Whenever `jev-run.sh` changes, bump `JEV_RUN_VERSION` in it AND the `grep` check in the jev `SKILL.md`, or
  existing installs keep the old launcher. CI checks the two match.

## License

[MIT](LICENSE). Third-party tools the plugins install keep their own licenses.
