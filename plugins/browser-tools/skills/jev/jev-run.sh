#!/bin/zsh
# Usage: jev-run.sh <url> "<goal>"
# Runs Jev against an isolated, headless Chrome (no window, separate profile, none of your logins).
# Env overrides: JEV_TEXT_MODEL (OpenRouter model for typed text), JEV_TIMEOUT (seconds, default 60).
# The text model is set HERE, not in .env: this launcher's value wins over any TEXT_MODEL line in .env.
[ $# -eq 2 ] || { echo 'usage: jev-run.sh <url> "<goal>"'; exit 2; }
cd "$(dirname "$0")"
PORT=9333

up() { curl -s -m 1 "http://127.0.0.1:$PORT/json/version" >/dev/null; }
if ! up; then
  nohup "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
    --remote-debugging-port=$PORT --user-data-dir="$HOME/tools/jev-chrome-profile" \
    --no-first-run --no-default-browser-check about:blank >/dev/null 2>&1 &
  for _ in {1..40}; do up && break; sleep 0.25; done
  up || { echo "headless Chrome did not start on port $PORT"; exit 1; }
fi

export TEXT_MODEL="${JEV_TEXT_MODEL:-anthropic/claude-haiku-5.5}"
export BU_CDP_URL="http://127.0.0.1:$PORT"
# Run in its own process group and kill the whole group if it runs past the limit (macOS has no `timeout`).
perl -e '
  $t = shift; $pid = fork;
  if (!$pid) { setpgrp(0, 0); exec @ARGV or die "exec failed: $!" }
  $SIG{ALRM} = sub { print STDERR "jev: stopped after ${t}s\n"; kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; exit 124 };
  alarm $t; waitpid($pid, 0); exit($? >> 8);
' "${JEV_TIMEOUT:-60}" uv run --env-file .env python examples/run.py --url "$1" --goal "$2"
