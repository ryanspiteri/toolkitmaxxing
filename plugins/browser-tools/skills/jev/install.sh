#!/usr/bin/env bash
# browser-tools installer (macOS). Idempotent; safe to re-run.
#   1. Agent Reach (read-only platform access), pinned release, plus its Claude skill
#   2. Jev Ultrafast (headless clicking agent), pinned commit, at ~/tools/jev-ultrafast
#   3. jev-run.sh launcher
# API keys are never shipped. A fresh Jev gets a blank .env; add your own
# TYPESAFE_API_KEY and TEXT_MODEL_API_KEY:  open -e ~/tools/jev-ultrafast/.env
# Needs: git, uv (https://docs.astral.sh/uv/), Google Chrome.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
claude_home="${CLAUDE_HOME:-$HOME/.claude}"

AGENT_REACH_URL="https://github.com/Panniantong/Agent-Reach/releases/download/v1.6.1/agent-reach.zip"
JEV_REPO="https://github.com/browser-use/jev-ultrafast.git"
JEV_COMMIT="cf3c406f0fc4becff8986ed4d4d37b7b9f102e45"   # tested 2026-11-21; bump only after re-testing
JEV_DIR="$HOME/tools/jev-ultrafast"

[ "$(uname)" = Darwin ] || { echo "macOS only for now"; exit 1; }
command -v git >/dev/null || { echo "git missing: xcode-select --install"; exit 1; }
command -v uv  >/dev/null || [ -x "$HOME/.local/bin/uv" ] || { echo "uv missing: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
[ -d "/Applications/Google Chrome.app" ] || { echo "Google Chrome missing: install it from google.com/chrome"; exit 1; }

# 1. Agent Reach
command -v agent-reach >/dev/null || uv tool install "agent-reach @ $AGENT_REACH_URL"
[ -e "$claude_home/skills/agent-reach" ] || agent-reach setup   # default channels + links its skill
echo "agent-reach -> $(uv tool list 2>/dev/null | grep -m1 '^agent-reach' || echo installed)"

# 2. Jev, pinned
mkdir -p "$HOME/tools"
[ -d "$JEV_DIR/.git" ] || git clone -q "$JEV_REPO" "$JEV_DIR"
if [ "$(git -C "$JEV_DIR" rev-parse HEAD)" != "$JEV_COMMIT" ]; then
  git -C "$JEV_DIR" fetch -q origin
  git -C "$JEV_DIR" -c advice.detachedHead=false checkout -q "$JEV_COMMIT"
fi
uv sync -q --project "$JEV_DIR"
echo "jev         -> $JEV_DIR @ ${JEV_COMMIT:0:7}"

# 3. Launcher and .env
cp "$here/jev-run.sh" "$JEV_DIR/jev-run.sh" && chmod +x "$JEV_DIR/jev-run.sh"
if [ ! -f "$JEV_DIR/.env" ]; then
  # The launcher sets the text model; drop the example's stale TEXT_MODEL line so there is one setting.
  grep -v '^TEXT_MODEL=' "$JEV_DIR/.env.example" > "$JEV_DIR/.env"
  echo "created blank $JEV_DIR/.env"
fi

missing=""
for k in TYPESAFE_API_KEY TEXT_MODEL_API_KEY; do
  grep -qE "^$k=.+" "$JEV_DIR/.env" || missing="$missing $k"
done
if [ -n "$missing" ]; then
  echo "Still needs your API keys in $JEV_DIR/.env:$missing"
  echo "  open -e $JEV_DIR/.env"
else
  echo "keys        -> present"
fi
