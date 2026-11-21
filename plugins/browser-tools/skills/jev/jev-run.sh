#!/usr/bin/env bash
# Usage: jev-run.sh <url> "<goal>"
#        jev-run.sh --stop    stop every Jev headless Chrome and Browser Harness helper
# Runs Jev (installed in ~/tools/jev-ultrafast) against an isolated, headless Chrome: no window, separate profile,
# none of your logins. Up to 8 tasks can run at once: each takes a free port in 9333..9340 and has its own profile.
# Settings (environment variables):
#   JEV_TEXT_MODEL           OpenRouter model for typed text (default anthropic/claude-haiku-5.5)
#   JEV_TEXT_MODEL_BASE_URL  API base URL for the text model (default https://openrouter.ai/api/v1, unless .env
#                            has a TEXT_MODEL_BASE_URL line or the environment sets TEXT_MODEL_BASE_URL)
#   JEV_TIMEOUT              seconds before the task is stopped, 1 to 3600, exit 124 (default 60)
#   JEV_FRESH=1              restart this port's Chrome with an empty profile before the run
#   JEV_CHROME               path to the Chrome/Chromium binary (default: auto-detect)
#   JEV_CHROME_ARGS          extra Chrome flags, e.g. --no-sandbox on a CI runner or container
#   JEV_HARNESS_HOME         Browser Harness home for Jev (default ~/tools/jev-ultrafast/.harness); set a shorter
#                            path if your home folder path is too long for its sockets
# ~/tools/jev-ultrafast/launcher.env may set defaults for JEV_CHROME, JEV_CHROME_ARGS, JEV_TEXT_MODEL,
# JEV_TEXT_MODEL_BASE_URL and JEV_TIMEOUT, one KEY=VALUE per line, value taken literally (no quotes). A variable
# set in the environment wins.
# The text model is set HERE, not in .env: this launcher's value wins over any TEXT_MODEL line in .env.
# Browser Harness (Jev's link to Chrome) keeps its own files in the Jev harness home, apart from any Browser
# Harness you use yourself.
# Exit codes: 0 the run finished (read the last status line, done or blocked), 1 Chrome or Jev failed,
# 2 usage or bad JEV_TIMEOUT, 75 all slots busy, 124 timed out, 127 a command was not found, 129 hung up
# (SIGHUP), 130 interrupted (SIGINT), 143 stopped (SIGTERM), other 128+N killed by signal N.

usage() { echo 'usage: jev-run.sh <url> "<goal>"   or   jev-run.sh --stop'; exit 2; }

# Whenever this file changes, bump JEV_RUN_VERSION and the matching check in SKILL.md.
# shellcheck disable=SC2034  # read by the upgrade check in SKILL.md
JEV_RUN_VERSION=1.2.0

find_chrome() {
  local mac="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" c
  if [ -n "${JEV_CHROME:-}" ]; then [ -x "$JEV_CHROME" ] || return 1; echo "$JEV_CHROME"; return 0; fi
  if [ -x "$mac" ]; then echo "$mac"; return 0; fi
  for c in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$c" && return 0
  done
  return 1
}

uid="$(id -u)"
# Something answers DevTools on this port.
up() { curl -sf -m 1 --noproxy '*' "http://127.0.0.1:$PORT/json/version" >/dev/null; }
# Our own Chrome for this port, matched by its profile path (the [j] keeps the pattern from matching itself).
chrome_running() { pgrep -U "$uid" -f "[j]ev-chrome-profile-$PORT( |\$)" >/dev/null; }
# Stop our Chrome for this port: TERM, up to 5 s to exit, then KILL and up to 2 s more.
stop_chrome() {
  pkill -U "$uid" -f "[j]ev-chrome-profile-$PORT( |\$)"
  for _ in {1..20}; do chrome_running || return 0; sleep 0.25; done
  pkill -KILL -U "$uid" -f "[j]ev-chrome-profile-$PORT( |\$)"
  for _ in {1..8}; do chrome_running || return 0; sleep 0.25; done
  return 1
}

# Jev's own Browser Harness home (sockets, logs, auth, settings), never the user's ~/.config/browser-harness.
# Overrides that would move part of it elsewhere are dropped, and its telemetry is off.
harness_env() {
  export BH_HOME="${JEV_HARNESS_HOME:-$HOME/tools/jev-ultrafast/.harness}"
  unset BH_CONFIG_DIR BH_RUNTIME_DIR BH_TMP_DIR BH_AGENT_WORKSPACE BH_AUTH_PATH BH_RUNTIME_DIR_SHARED BH_TMP_DIR_SHARED
  export BH_TELEMETRY=0
}

# --stop: shut down each Jev helper through Browser Harness itself (by name, in Jev's harness home, so a
# Browser Harness of your own is never touched), then every Jev headless Chrome.
stop_all() {
  local py="$HOME/tools/jev-ultrafast/.venv/bin/python" ports="" p
  harness_env
  if [ -d "$BH_HOME" ] && [ -x "$py" ]; then
    "$py" -I -c '
from browser_harness import admin
stopped = 0
for port in range(9333, 9341):
    name = "jev-%d" % port
    if admin.daemon_alive(name):
        try:
            admin.restart_daemon(name)
            print("stopped helper " + name)
            stopped += 1
        except Exception as e:
            print("could not stop helper %s: %s" % (name, e))
if not stopped:
    print("no Jev helpers running")
'
  else
    echo "no Jev helpers running"
  fi
  for p in 9333 9334 9335 9336 9337 9338 9339 9340; do
    PORT="$p"
    if chrome_running; then ports="$ports $p"; fi
  done
  pkill -U "$uid" -f '[j]ev-chrome-profile-'
  for _ in {1..20}; do pgrep -U "$uid" -f '[j]ev-chrome-profile-' >/dev/null || break; sleep 0.25; done
  if pgrep -U "$uid" -f '[j]ev-chrome-profile-' >/dev/null; then
    pkill -KILL -U "$uid" -f '[j]ev-chrome-profile-'
    for _ in {1..12}; do pgrep -U "$uid" -f '[j]ev-chrome-profile-' >/dev/null || break; sleep 0.25; done
  fi
  if [ -n "$ports" ]; then echo "stopped Jev Chrome on port(s):$ports"; else echo "no Jev Chrome running"; fi
}

# Stage 2, started by the perl wrapper below while it holds the lock for $JEV_PORT. Runs in its own
# process group, which the wrapper kills on timeout or interrupt. Chrome is started outside that group.
run_task() {
  PORT="$JEV_PORT"
  [ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 1; }
  PROFILE="$HOME/tools/jev-chrome-profile-$PORT"

  # Orphan guard. fd 9 is a pipe whose only write end the launcher holds. If the launcher dies for any
  # reason (kill -9, hangup, its caller's group killed), the read hits end-of-file and this watcher kills
  # the task's process group: TERM, then KILL after 2 s.
  perl -e '
    my $uid = shift;
    open(my $guard, "<&=", 9) or exit 0;
    1 while (sysread($guard, my $buf, 512) // ($!{EINTR} ? 1 : 0));
    $SIG{TERM} = "IGNORE";
    my $group = getpgrp();
    kill "TERM", -$group;
    for (1 .. 20) {
      open(my $ps, "-|", "pgrep", "-U", $uid, "-g", $group) or last;
      my @others = grep { $_ != $$ } map { 0 + $_ } <$ps>;
      close $ps;
      last unless @others;
      select(undef, undef, undef, 0.1);
    }
    kill "KILL", -$group;
  ' "$uid" </dev/null >/dev/null 2>&1 &

  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null || { echo "uv not found; run the installer"; exit 1; }

  harness_env
  { mkdir -p "$BH_HOME" && chmod 700 "$BH_HOME"; } || { echo "cannot create $BH_HOME"; exit 1; }
  # Browser Harness puts each helper's socket at <home>/runtime/bu-<name>.sock, with the home's symlinks
  # resolved; a Unix socket path must stay short (104 bytes on macOS).
  sock="$(cd "$BH_HOME" && pwd -P)/runtime/bu-jev-9340.sock"
  if [ "$(printf '%s' "$sock" | wc -c)" -gt 100 ]; then
    echo "the Browser Harness socket path would be too long: $sock"
    echo "use a shorter home folder path, or set JEV_HARNESS_HOME to a short folder of your own"
    exit 1
  fi

  if [ "${JEV_FRESH:-}" = 1 ]; then
    stop_chrome || { echo "could not stop Chrome on port $PORT"; exit 1; }
    case "$PROFILE" in
      "$HOME/tools/jev-chrome-profile-"[0-9][0-9][0-9][0-9]) rm -rf "$PROFILE" ;;
      *) echo "refusing to delete $PROFILE"; exit 1 ;;
    esac
    [ ! -e "$PROFILE" ] || { echo "could not delete $PROFILE"; exit 1; }
  fi

  # Fail closed: only ever attach to our own Chrome for this port.
  if up; then
    chrome_running || { echo "port $PORT is answered by something that is not Jev's Chrome; not attaching"; exit 1; }
  else
    if chrome_running; then
      stop_chrome || { echo "could not stop the unresponsive Chrome on port $PORT"; exit 1; }
    fi
    CHROME="$(find_chrome)" || { echo "Chrome not found: install Google Chrome or Chromium, or set JEV_CHROME"; exit 1; }
    read -r -a chrome_extra <<< "${JEV_CHROME_ARGS:-}"
    # setpgrp puts Chrome in its own process group (macOS has no setsid), so stopping a task leaves
    # Chrome running for the next one. It does not get the guard pipe.
    nohup perl -e 'setpgrp(0, 0); exec @ARGV or die "cannot start Chrome: $!\n"' "$CHROME" --headless=new \
      --remote-debugging-port="$PORT" --user-data-dir="$PROFILE" \
      --no-first-run --no-default-browser-check "${chrome_extra[@]}" about:blank >/dev/null 2>&1 9<&- &
    for _ in {1..40}; do up && chrome_running && break; sleep 0.25; done
    if ! { up && chrome_running; }; then
      stop_chrome
      echo "headless Chrome did not start on port $PORT (is another program using that port?)"
      exit 1
    fi
  fi
  # With a fixed port Chrome may not write DevToolsActivePort; when it does, it must name this port.
  if [ -f "$PROFILE/DevToolsActivePort" ] && [ "$(head -n 1 "$PROFILE/DevToolsActivePort")" != "$PORT" ]; then
    echo "Chrome for $PROFILE is not listening on port $PORT; not attaching"
    exit 1
  fi

  export TEXT_MODEL="${JEV_TEXT_MODEL:-anthropic/claude-haiku-5.5}"
  # Jev's own default endpoint is not OpenRouter. .env loaded by uv never overrides the environment, so the
  # default is set only when neither .env nor the environment sets one.
  if [ -n "${JEV_TEXT_MODEL_BASE_URL:-}" ]; then
    export TEXT_MODEL_BASE_URL="$JEV_TEXT_MODEL_BASE_URL"
  elif [ -z "${TEXT_MODEL_BASE_URL:-}" ] && ! grep -q '^TEXT_MODEL_BASE_URL=.' .env 2>/dev/null; then
    export TEXT_MODEL_BASE_URL="https://openrouter.ai/api/v1"
  fi
  export BU_CDP_URL="http://127.0.0.1:$PORT"
  # Empty means "not set" to Browser Harness; a value here would point it at another browser.
  export BU_CDP_WS='' BU_BROWSER_ID=''
  # One Browser Harness daemon per port. Unnamed, every run would share the "default" daemon and drive
  # whichever Chrome that daemon attached to first.
  export BU_NAME="jev-$PORT"
  NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
  no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"
  export NO_PROXY no_proxy
  exec uv run --frozen --env-file .env python examples/run.py --url="$1" --goal="$2" 9<&-
}

if [ "${1:-}" = __run ] && [ $# -eq 3 ]; then
  case "${JEV_PORT:-}" in 933[3-9]|9340) run_task "$2" "$3" ;; esac
  usage
fi

# Stage 1.
case "$#:${1:-}" in 1:--stop|2:*) ;; *) usage ;; esac
[ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 1; }
if [ $# -eq 1 ]; then stop_all; exit 0; fi
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$HOME/tools/jev-ultrafast" || { echo "Jev is not installed in $HOME/tools/jev-ultrafast: run install.sh"; exit 1; }

# Defaults from launcher.env: read as plain text (never sourced), only the keys above.
conf="$HOME/tools/jev-ultrafast/launcher.env"
if [ -f "$conf" ]; then
  keys=" JEV_CHROME JEV_CHROME_ARGS JEV_TEXT_MODEL JEV_TEXT_MODEL_BASE_URL JEV_TIMEOUT "
  from_env=" "
  for k in $keys; do
    if printenv "$k" >/dev/null; then from_env="$from_env$k "; fi
  done
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    k="${line%%=*}"
    [ "$k" != "$line" ] || continue
    case "$keys" in *" $k "*) ;; *) continue ;; esac
    case "$from_env" in *" $k "*) continue ;; esac
    export "$k=${line#*=}"
  done < "$conf"
fi

timeout="${JEV_TIMEOUT:-60}"
case "$timeout" in
  [1-9]|[1-9][0-9]|[1-9][0-9][0-9]|[1-9][0-9][0-9][0-9]) [ "$timeout" -le 3600 ] ;;
  *) false ;;
esac || { echo "JEV_TIMEOUT must be a whole number of seconds from 1 to 3600"; exit 2; }

LOCKS="$HOME/tools/.jev-locks"
mkdir -p "$LOCKS" || { echo "cannot create $LOCKS"; exit 1; }

# Perl takes the first free port with a kernel lock (flock) and holds it for the whole run. The kernel
# drops the lock when perl exits, however it exits, so a crashed run never leaves a stale lock.
# The task runs as stage 2 in its own process group; on timeout, SIGINT, SIGTERM or SIGHUP the whole group
# is killed (macOS has no `timeout`). The guard pipe's write end stays here, so the group also dies if this
# process is killed outright.
exec perl -MFcntl=:DEFAULT,:flock -MPOSIX=SIGHUP,SIGINT,SIGTERM,SIG_BLOCK,SIG_UNBLOCK,sigprocmask -e '
  my ($locks, $t, $self, $url, $goal) = @ARGV;
  my ($lock, $port);
  for my $p (9333 .. 9340) {
    sysopen(my $fh, "$locks/$p.lock", O_RDWR | O_CREAT, 0600)
      or do { print "cannot open $locks/$p.lock: $!\n"; exit 1 };
    if (flock($fh, LOCK_EX | LOCK_NB)) { ($lock, $port) = ($fh, $p); last }
    unless ($!{EWOULDBLOCK} || $!{EAGAIN}) { print "cannot lock $locks/$p.lock: $!\n"; exit 1 }
    close $fh;
  }
  unless ($lock) { print "all 8 Jev slots busy\n"; exit 75 }
  $ENV{JEV_PORT} = $port;
  pipe(my $guard_r, my $guard_w) or do { print "pipe failed: $!\n"; exit 1 };

  # Hold the signals until the child has its own process group and the handlers are set.
  my $sigs = POSIX::SigSet->new(SIGHUP, SIGINT, SIGTERM);
  sigprocmask(SIG_BLOCK, $sigs);
  my $pid = fork;
  unless (defined $pid) { print "fork failed: $!\n"; exit 1 }
  unless ($pid) {
    setpgrp(0, 0);
    close $guard_w;
    # The task reads the guard pipe as fd 9, kept open across exec.
    my $fd = fileno($guard_r);
    if ($fd != 9) { defined POSIX::dup2($fd, 9) or POSIX::_exit(1) }
    open(my $nine, "<&=", 9) or POSIX::_exit(1);
    fcntl($nine, F_SETFD, 0) or POSIX::_exit(1);
    sigprocmask(SIG_UNBLOCK, $sigs);
    exec("bash", $self, "__run", $url, $goal) or do { print STDERR "exec failed: $!\n"; POSIX::_exit(1) };
  }
  close $guard_r;
  setpgrp($pid, $pid);
  sub stop { my ($code, $wait) = @_; kill "TERM", -$pid; sleep $wait; kill "KILL", -$pid; exit $code }
  $SIG{ALRM} = sub { print STDERR "jev: stopped after ${t}s\n"; stop(124, 2) };
  $SIG{HUP}  = sub { stop(129, 1) };
  $SIG{INT}  = sub { stop(130, 1) };
  $SIG{TERM} = sub { stop(143, 1) };
  sigprocmask(SIG_UNBLOCK, $sigs);
  alarm $t;
  waitpid($pid, 0);
  exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
' "$LOCKS" "$timeout" "$self" "$1" "$2"
