#!/usr/bin/env bash
# browser-tools installer (macOS and Linux). Idempotent; safe to re-run.
#   1. Agent Reach (read-only platform access), pinned release checked against its sha256 and kept in
#      ~/tools/agent-reach, plus its skill
#   2. Jev Ultrafast (headless clicking agent), pinned commit, at ~/tools/jev-ultrafast
#   3. jev-run.sh launcher, and the jev skill copied to ~/.agents/skills/jev for Codex and Kimi Code
# API keys are never shipped. A fresh Jev gets a blank .env; add your own
# TYPESAFE_API_KEY and TEXT_MODEL_API_KEY in ~/tools/jev-ultrafast/.env
# Needs: git, uv (https://docs.astral.sh/uv/), curl, perl, pgrep and pkill, and Google Chrome or Chromium
# (JEV_CHROME points at another binary).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
claude_home="${CLAUDE_HOME:-$HOME/.claude}"
agents_skills="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"   # where the jev copy goes for Codex and Kimi Code

AGENT_REACH_URL="https://github.com/Panniantong/Agent-Reach/releases/download/v1.6.1/agent-reach.zip"
AGENT_REACH_SHA256="51443d733bcb26064262442083a8f8abf6ba5e3e7df54beebafe98c88be04a60"
JEV_REPO="https://github.com/browser-use/jev-ultrafast.git"
JEV_COMMIT="cf3c406f0fc4becff8986ed4d4d37b7b9f102e45"   # tested 2026-11-21; bump only after re-testing
JEV_DIR="$HOME/tools/jev-ultrafast"

if [ "$(uname)" = Darwin ]; then
  git_hint="xcode-select --install"
  edit_cmd="open -e"
else
  git_hint="install it with your package manager, e.g. sudo apt install git"
  edit_cmd="${EDITOR:-nano}"
fi
command -v git >/dev/null || { echo "git missing: $git_hint"; exit 1; }
command -v uv  >/dev/null || [ -x "$HOME/.local/bin/uv" ] || { echo "uv missing: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }
tools_missing=""
for t in curl perl pkill pgrep; do
  if ! command -v "$t" >/dev/null; then
    case "$t" in pkill|pgrep) pkg=procps ;; *) pkg="$t" ;; esac
    echo "$t missing: install it with your package manager, e.g. sudo apt install $pkg"
    tools_missing=1
  fi
done
[ -z "$tools_missing" ] || exit 1
export PATH="$HOME/.local/bin:$PATH"
chrome_ok=""
if [ -n "${JEV_CHROME:-}" ]; then
  if [ -x "$JEV_CHROME" ]; then chrome_ok=1; fi
elif [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  chrome_ok=1
else
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$c" >/dev/null; then chrome_ok=1; fi
  done
fi
[ -n "$chrome_ok" ] || { echo "Chrome missing: install Google Chrome (google.com/chrome) or Chromium, or set JEV_CHROME"; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# 1. Agent Reach, installed from a kept copy of the pinned release (so `uv tool upgrade` keeps a valid source).
# Installs when agent-reach is missing, or when uv has a different version than the pin (bump the pin to update).
reach_version="${AGENT_REACH_URL#*/download/v}"
reach_version="${reach_version%%/*}"
reach_zip="$HOME/tools/agent-reach/agent-reach-$reach_version.zip"
reach_installed="$(uv tool list 2>/dev/null | sed -n 's/^agent-reach v//p' || true)"
reach_changed=""
if ! command -v agent-reach >/dev/null || { [ -n "$reach_installed" ] && [ "$reach_installed" != "$reach_version" ]; }; then
  mkdir -p "$HOME/tools/agent-reach"
  if [ ! -f "$reach_zip" ] || [ "$(sha256_of "$reach_zip")" != "$AGENT_REACH_SHA256" ]; then
    curl -fsSL -o "$reach_zip.part" "$AGENT_REACH_URL" || { rm -f "$reach_zip.part"; echo "could not download $AGENT_REACH_URL"; exit 1; }
    mv "$reach_zip.part" "$reach_zip"
  fi
  got="$(sha256_of "$reach_zip")"
  if [ "$got" != "$AGENT_REACH_SHA256" ]; then
    rm -f "$reach_zip"
    echo "agent-reach zip sha256 is $got, expected $AGENT_REACH_SHA256. Not installing it."
    exit 1
  fi
  echo "agent-reach zip -> $reach_zip (sha256 ok)"
  uv tool install "agent-reach @ file://$reach_zip"
  reach_changed=1
fi
# Run setup after (re)installing Agent Reach, when its own skill copy is missing (it always puts it in
# ~/.agents/skills, whatever AGENTS_SKILLS_DIR says), or when Claude Code is present and has no link to it.
if [ -n "$reach_changed" ] || [ ! -f "$HOME/.agents/skills/agent-reach/SKILL.md" ] \
  || { [ -d "$claude_home" ] && [ ! -e "$claude_home/skills/agent-reach" ]; }; then
  # Default channels + links its skill. No prompts; its long JSON report is shown only if setup fails.
  setup_out="$(agent-reach setup </dev/null 2>&1)" || { echo "$setup_out"; echo "agent-reach setup failed"; exit 1; }
fi
echo "agent-reach -> $(uv tool list 2>/dev/null | grep -m1 '^agent-reach' || echo installed)"

# 2. Jev, pinned
mkdir -p "$HOME/tools"
[ -d "$JEV_DIR/.git" ] || git clone -q "$JEV_REPO" "$JEV_DIR"
if [ "$(git -C "$JEV_DIR" rev-parse HEAD)" != "$JEV_COMMIT" ]; then
  git -C "$JEV_DIR" fetch -q origin
  git -C "$JEV_DIR" -c advice.detachedHead=false checkout -q "$JEV_COMMIT"
fi
cd "$JEV_DIR"
uv sync -q --frozen --project "$JEV_DIR"
echo "jev         -> $JEV_DIR @ ${JEV_COMMIT:0:7}"

# 3. Launcher, .env and launcher.env
cp "$here/jev-run.sh" "$JEV_DIR/jev-run.sh" && chmod +x "$JEV_DIR/jev-run.sh"
if [ ! -f "$JEV_DIR/.env" ]; then
  # The launcher sets the text model; drop the example's stale TEXT_MODEL line so there is one setting.
  grep -v '^TEXT_MODEL=' "$JEV_DIR/.env.example" > "$JEV_DIR/.env"
  echo "created blank $JEV_DIR/.env"
fi
chmod 600 "$JEV_DIR/.env"   # it holds your API keys
# Keep the Chrome settings given to the installer, so later runs use them without setting them again.
conf="$JEV_DIR/launcher.env"
if [ ! -f "$conf" ] && { [ -n "${JEV_CHROME:-}" ] || [ -n "${JEV_CHROME_ARGS:-}" ]; }; then
  {
    if [ -n "${JEV_CHROME:-}" ]; then echo "JEV_CHROME=$JEV_CHROME"; fi
    if [ -n "${JEV_CHROME_ARGS:-}" ]; then echo "JEV_CHROME_ARGS=$JEV_CHROME_ARGS"; fi
  } > "$conf"
  echo "saved JEV_CHROME / JEV_CHROME_ARGS in $conf"
fi
# Version 1.0.0 ran one Chrome on an unsuffixed profile. Stop it; the per-port profiles are not touched.
if [ -e "$HOME/tools/jev-chrome-profile" ]; then
  pkill -U "$(id -u)" -f '[j]ev-chrome-profile( |$)' || true
  echo "old profile $HOME/tools/jev-chrome-profile is no longer used; you can delete it"
fi
# Before 1.2.0, Jev used Browser Harness's shared "default" helper in ~/.config/browser-harness. If one started
# by Jev is still running, say so; never stop it, since your own Browser Harness may be using it.
old_pid="$(cat "$HOME/.config/browser-harness/runtime/bu-default.pid" 2>/dev/null || true)"
case "$old_pid" in
  ''|*[!0-9]*) ;;
  *)
    if ps -o command= -p "$old_pid" 2>/dev/null | grep -qF "$JEV_DIR/.venv/bin/python -m browser_harness.daemon"; then
      echo "note: a Browser Harness helper started by an older Jev is still running (pid $old_pid, in"
      echo "  ~/.config/browser-harness). Jev no longer uses it. If you do not use Browser Harness yourself,"
      echo "  stop it with: $JEV_DIR/.venv/bin/browser-harness --reload"
    fi
    ;;
esac

# 4. Shared skill for Codex and Kimi Code (Claude Code gets it from the plugin instead)
mkdir -p "$agents_skills/jev"
if [ "$(cd "$agents_skills/jev" && pwd -P)" != "$(cd "$here" && pwd -P)" ]; then
  cp "$here/SKILL.md" "$here/install.sh" "$here/jev-run.sh" "$agents_skills/jev/"
  chmod +x "$agents_skills/jev/install.sh" "$agents_skills/jev/jev-run.sh"
fi
echo "shared skill -> $agents_skills/jev (Codex, Kimi Code)"

missing=""
for k in TYPESAFE_API_KEY TEXT_MODEL_API_KEY; do
  grep -qE "^$k=.+" "$JEV_DIR/.env" || missing="$missing $k"
done
if [ -n "$missing" ]; then
  echo "Still needs your API keys in $JEV_DIR/.env:$missing"
  echo "  $edit_cmd $JEV_DIR/.env"
else
  echo "keys        -> present"
fi
