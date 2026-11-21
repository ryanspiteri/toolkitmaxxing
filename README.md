# toolkitmaxxing

Small, tested tools and skills for [Claude Code](https://claude.com/claude-code), shared as a plugin marketplace.

## Install

In your terminal:

```bash
claude plugin marketplace add ryanspiteri/toolkitmaxxing
claude plugin install browser-tools@toolkitmaxxing
```

Or inside Claude Code: `/plugin marketplace add ryanspiteri/toolkitmaxxing`, then `/plugin` to browse.

The repo is private: you need to be added as a collaborator, and `gh auth login` (or a git credential) on your
machine so Claude Code can clone it.

Get updates later with `claude plugin marketplace update toolkitmaxxing`.

## Tools

| Plugin | What it does | Needs |
|---|---|---|
| [browser-tools](plugins/browser-tools/) | `jev` skill: a headless browser agent that clicks through public sites in about 3 to 10 seconds, with no window. Installs [Agent Reach](https://github.com/Panniantong/Agent-Reach) too, for read-only access to Reddit, YouTube transcripts, X, GitHub and more. | macOS, git, uv, Chrome, your own TypeSafe and OpenRouter keys |

## Rules for adding a tool

- One folder per plugin under `plugins/`, with `.claude-plugin/plugin.json`, its skills, and a README.
- No keys, tokens, personal paths or private business details, ever. Each person brings their own keys.
- Third-party code is installed from its own repo at a pinned version, never copied in.
- Test it on a real machine before it goes in, and say in its README what was tested and when.
- Run `claude plugin validate .` before pushing.
