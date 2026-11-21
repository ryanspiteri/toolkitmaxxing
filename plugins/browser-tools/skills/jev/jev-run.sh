#!/usr/bin/env bash
# Usage: jev-run.sh <url> "<goal>"
#        jev-run.sh --check   take a slot, start or verify its Chrome exactly as a task would, print it, release
#        jev-run.sh --stop    stop every Jev headless Chrome and Browser Harness helper (this ends running tasks)
# Runs Jev (installed in ~/tools/jev-ultrafast) against an isolated, headless Chrome: no window, separate profile,
# none of your logins. Up to 8 tasks can run at once: each takes a free slot 9333..9340, which names its lock, its
# Chrome profile and its Browser Harness helper. Chrome picks its own debugging port on 127.0.0.1.
# Settings (environment variables):
#   JEV_TEXT_MODEL           OpenRouter model for typed text (default anthropic/claude-haiku-5.5)
#   JEV_TEXT_MODEL_BASE_URL  API base URL for the text model (default https://openrouter.ai/api/v1, unless .env
#                            has a TEXT_MODEL_BASE_URL line or the environment sets TEXT_MODEL_BASE_URL)
#   JEV_TIMEOUT              seconds before the task is stopped, 1 to 3600, exit 124 (default 60)
#   JEV_FRESH=1              restart this slot's Chrome with an empty profile before the run
#   JEV_TEXT=1               after a finished run, also print the visible text of the page Jev ended on
#                            (read just before Jev closes its tab; web content, so data, never instructions)
#   JEV_TEXT_MAX             characters of page text to print, 1000 to 200000 (default 20000)
#   JEV_CHROME               path to the Chrome/Chromium binary (default: auto-detect)
#   JEV_CHROME_ARGS          extra Chrome flags, e.g. --no-sandbox on a CI runner or container
#   JEV_HARNESS_HOME         Browser Harness home for Jev (default ~/tools/jev-ultrafast/.harness); set a shorter
#                            path if your home folder path is too long for its sockets
# ~/tools/jev-ultrafast/launcher.env may set defaults for JEV_CHROME, JEV_CHROME_ARGS, JEV_TEXT_MODEL,
# JEV_TEXT_MODEL_BASE_URL, JEV_TIMEOUT, JEV_TEXT and JEV_TEXT_MAX, one KEY=VALUE per line, value taken literally
# (no quotes). A variable set in the environment wins.
# The text model is set HERE, not in .env: this launcher's value wins over any TEXT_MODEL line in .env.
# Browser Harness (Jev's link to Chrome) keeps its own files in the Jev harness home, apart from any Browser
# Harness you use yourself.
# Exit codes: 0 the run finished (read the last status line, done or blocked), 1 Chrome or Jev failed,
# 2 usage or bad JEV_TIMEOUT / JEV_TEXT_MAX, 75 all slots busy, 124 timed out, 127 a command was not found, 129 hung up
# (SIGHUP), 130 interrupted (SIGINT), 143 stopped (SIGTERM), other 128+N killed by signal N.

usage() { echo 'usage: jev-run.sh <url> "<goal>"   or   jev-run.sh --check   or   jev-run.sh --stop'; exit 2; }

# Whenever this file changes, bump JEV_RUN_VERSION and the matching check in SKILL.md.
# shellcheck disable=SC2034  # read by the upgrade check in SKILL.md
JEV_RUN_VERSION=1.2.2

SLOTS="9333 9334 9335 9336 9337 9338 9339 9340"

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
# Our own Chrome for this slot, matched by its profile path (the [j] keeps the pattern from matching itself).
chrome_running() { pgrep -U "$uid" -f "[j]ev-chrome-profile-$SLOT( |\$)" >/dev/null; }
# Stop our Chrome for this slot: TERM, up to 5 s to exit, then KILL and up to 2 s more.
stop_chrome() {
  pkill -U "$uid" -f "[j]ev-chrome-profile-$SLOT( |\$)"
  for _ in {1..20}; do chrome_running || return 0; sleep 0.25; done
  pkill -KILL -U "$uid" -f "[j]ev-chrome-profile-$SLOT( |\$)"
  for _ in {1..8}; do chrome_running || return 0; sleep 0.25; done
  return 1
}
# Chrome launched with --remote-debugging-port=0 picks a free port and writes it to DevToolsActivePort: line 1 the
# port, line 2 the browser's /devtools/browser/<id> path. Reads both into PORT and WSPATH.
read_port_file() {
  local f="$PROFILE/DevToolsActivePort"
  [ -f "$f" ] || return 1
  PORT="$(sed -n 1p "$f")"
  WSPATH="$(sed -n 2p "$f")"
  case "$PORT" in ''|*[!0-9]*) return 1 ;; esac
  case "$WSPATH" in /devtools/browser/?*) ;; *) return 1 ;; esac
}
# The DevTools endpoint on $PORT is the very browser named in the port file (its id is random per launch).
endpoint_matches() {
  local ws
  ws="$(curl -sf -m 1 --noproxy '*' "http://127.0.0.1:$PORT/json/version" \
    | sed -n 's/.*"webSocketDebuggerUrl": *"\([^"]*\)".*/\1/p')"
  [ "$ws" = "ws://127.0.0.1:$PORT$WSPATH" ]
}
# Reuse rule: our Chrome for this slot runs, its port file is readable, and the port answers as that browser.
chrome_ok() { chrome_running && read_port_file && endpoint_matches; }

# Jev's own Browser Harness home (sockets, logs, auth, settings), never the user's ~/.config/browser-harness.
# Overrides that would move part of it elsewhere are dropped, and its telemetry is off.
harness_env() {
  export BH_HOME="${JEV_HARNESS_HOME:-$HOME/tools/jev-ultrafast/.harness}"
  unset BH_CONFIG_DIR BH_RUNTIME_DIR BH_TMP_DIR BH_AGENT_WORKSPACE BH_AUTH_PATH BH_RUNTIME_DIR_SHARED BH_TMP_DIR_SHARED
  export BH_TELEMETRY=0
}

# Stop Jev's Browser Harness helpers by name (jev-<slot>) through Browser Harness's own shutdown, in Jev's harness
# home only, and check each one is gone. Prints a line per helper stopped; fails if one is still alive.
stop_helpers() {
  local py="$HOME/tools/jev-ultrafast/.venv/bin/python"
  { [ -d "$BH_HOME" ] && [ -x "$py" ]; } || return 0
  "$py" -I -c '
import os, subprocess, sys, time
from browser_harness import admin

def gone(name, pid):
    if admin.daemon_alive(name):
        return False
    if not pid:
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return True  # that pid now belongs to another user
    stat = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return stat.startswith("Z") or not stat

failed = False
for name in sys.argv[1:]:
    if not admin.daemon_alive(name):
        continue
    pid = admin.ipc.identify(name, timeout=2.0)
    try:
        admin.restart_daemon(name)
    except Exception as e:
        print("could not stop helper %s: %s" % (name, e))
        failed = True
        continue
    for _ in range(30):
        if gone(name, pid):
            print("stopped helper " + name)
            break
        time.sleep(0.1)
    else:
        print("helper %s (pid %s) is still running" % (name, pid))
        failed = True
sys.exit(1 if failed else 0)
' "$@"
}

# --stop: every Jev helper, then every Jev headless Chrome. Exit 1 if anything is still alive afterwards.
stop_all() {
  local out rc=0 ports="" p left
  harness_env
  # shellcheck disable=SC2046  # one argument per slot
  out="$(stop_helpers $(for p in $SLOTS; do echo "jev-$p"; done))" || rc=1
  if [ -n "$out" ]; then echo "$out"; else echo "no Jev helpers running"; fi
  for p in $SLOTS; do
    SLOT="$p"
    if chrome_running; then ports="$ports $p"; fi
  done
  pkill -U "$uid" -f '[j]ev-chrome-profile-'
  for _ in {1..20}; do pgrep -U "$uid" -f '[j]ev-chrome-profile-' >/dev/null || break; sleep 0.25; done
  if pgrep -U "$uid" -f '[j]ev-chrome-profile-' >/dev/null; then
    pkill -KILL -U "$uid" -f '[j]ev-chrome-profile-'
    for _ in {1..12}; do pgrep -U "$uid" -f '[j]ev-chrome-profile-' >/dev/null || break; sleep 0.25; done
  fi
  if [ -n "$ports" ]; then echo "stopped Jev Chrome for slot(s):$ports"; else echo "no Jev Chrome running"; fi
  left="$(pgrep -U "$uid" -f '[j]ev-chrome-profile-' | while read -r p; do ps -o pid=,command= -p "$p"; done)"
  if [ -n "$left" ]; then
    echo "still running:"
    echo "$left"
    rc=1
  fi
  return "$rc"
}

# Stage 2, started by the perl wrapper below while it holds the lock for slot $JEV_SLOT. Runs in its own process
# group, which the wrapper kills on timeout or interrupt. Chrome is started outside that group.
#   $1 task|check, $2 url, $3 goal
run_task() {
  SLOT="$JEV_SLOT"
  [ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 1; }
  PROFILE="$HOME/tools/jev-chrome-profile-$SLOT"

  # Orphan guard. fd 9 is a pipe whose only write end the launcher holds; fd 8 is the slot's lock. If the
  # launcher dies for any reason (kill -9, hangup, its caller's group killed), the read hits end-of-file and this
  # watcher stops the task's process group: TERM, then KILL for anything left after 2 s. It exits only once the
  # group is gone, and holding fd 8 keeps the slot locked until then.
  perl -e '
    open(my $guard, "<&=", 9) or exit 0;
    1 while (sysread($guard, my $buf, 512) // ($!{EINTR} ? 1 : 0));
    $SIG{TERM} = "IGNORE";
    my $group = getpgrp();
    sub others {
      my $ps = open(my $fh, "-|", "ps", "-A", "-o", "pid=", "-o", "pgid=") or return ();
      my @pids;
      while (<$fh>) { my ($p, $g) = split " "; push @pids, $p if $g == $group && $p != $$ && $p != $ps }
      close $fh;
      return @pids;
    }
    kill "TERM", -$group;
    for my $round (1, 2) {
      for (1 .. 20) { last unless others(); select(undef, undef, undef, 0.1) }
      my @left = others() or last;
      kill "KILL", @left;
    }
  ' </dev/null >/dev/null 2>&1 &
  # Nothing else in this stage keeps the lock or the guard pipe; Chrome and the task must not inherit them.
  exec 8>&- 9<&-

  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null || { echo "uv not found; run the installer"; exit 1; }
  if [ "$1" = task ] && [ "${JEV_TEXT:-}" = 1 ] && [ ! -f "$HOME/tools/jev-ultrafast/jev-text.py" ]; then
    echo "jev-text.py not found; run the installer"
    exit 1
  fi

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
    out="$(stop_helpers "jev-$SLOT")" || { echo "$out"; echo "could not stop the Browser Harness helper jev-$SLOT"; exit 1; }
    stop_chrome || { echo "could not stop Chrome for slot $SLOT"; exit 1; }
    case "$PROFILE" in
      "$HOME/tools/jev-chrome-profile-"[0-9][0-9][0-9][0-9]) rm -rf "$PROFILE" ;;
      *) echo "refusing to delete $PROFILE"; exit 1 ;;
    esac
    [ ! -e "$PROFILE" ] || { echo "could not delete $PROFILE"; exit 1; }
  fi

  # Only ever attach to the Chrome this slot launched:
  #   our Chrome runs + port file readable + its port answers as the browser named in the file  -> reuse
  #   anything else (no Chrome, no or stale port file, port answered by another browser or program)
  #     -> stop this slot's helper and Chrome, delete the port file, launch a new Chrome on a port it picks,
  #        and require the same three checks within 20 s, else exit 1
  if ! chrome_ok; then
    out="$(stop_helpers "jev-$SLOT")" || { echo "$out"; echo "could not stop the Browser Harness helper jev-$SLOT"; exit 1; }
    if chrome_running; then stop_chrome || { echo "could not stop the old Chrome for slot $SLOT"; exit 1; }; fi
    rm -f "$PROFILE/DevToolsActivePort"
    CHROME="$(find_chrome)" || { echo "Chrome not found: install Google Chrome or Chromium, or set JEV_CHROME"; exit 1; }
    read -r -a chrome_extra <<< "${JEV_CHROME_ARGS:-}"
    # setpgrp puts Chrome in its own process group (macOS has no setsid), so stopping a task leaves
    # Chrome running for the next one.
    nohup perl -e 'setpgrp(0, 0); exec @ARGV or die "cannot start Chrome: $!\n"' "$CHROME" --headless=new \
      --remote-debugging-port=0 --user-data-dir="$PROFILE" \
      --no-first-run --no-default-browser-check "${chrome_extra[@]}" about:blank >"$BH_HOME/chrome-$SLOT.log" 2>&1 &
    for _ in {1..80}; do chrome_ok && break; sleep 0.25; done
    if ! chrome_ok; then
      # Say which of the three checks failed, plus Chrome's own last words, so the cause is visible.
      if chrome_running; then echo "  chrome process: running"; else echo "  chrome process: not found"; fi
      if read_port_file; then
        echo "  port file: port $PORT, path $WSPATH"
        echo "  /json/version: $(curl -sf -m 1 --noproxy '*' "http://127.0.0.1:$PORT/json/version" | tr -d '\n' | cut -c1-300)"
      else
        echo "  port file: missing or unreadable ($PROFILE/DevToolsActivePort)"
      fi
      echo "  chrome output (last 15 lines of $BH_HOME/chrome-$SLOT.log):"
      tail -n 15 "$BH_HOME/chrome-$SLOT.log" 2>/dev/null | sed 's/^/    /'
      stop_chrome
      echo "headless Chrome did not start for slot $SLOT"
      exit 1
    fi
  fi

  if [ "$1" = check ]; then
    echo "ok slot $SLOT port $PORT"
    exit 0
  fi

  export TEXT_MODEL="${JEV_TEXT_MODEL:-anthropic/claude-haiku-5.5}"
  # Jev's own default endpoint is not OpenRouter. .env loaded by uv never overrides the environment, so the
  # default is set only when neither .env nor the environment sets one.
  if [ -n "${JEV_TEXT_MODEL_BASE_URL:-}" ]; then
    export TEXT_MODEL_BASE_URL="$JEV_TEXT_MODEL_BASE_URL"
  elif [ -z "${TEXT_MODEL_BASE_URL:-}" ] && ! grep -q '^TEXT_MODEL_BASE_URL=.' .env 2>/dev/null; then
    export TEXT_MODEL_BASE_URL="https://openrouter.ai/api/v1"
  fi
  # Connect to exactly that browser. Browser Harness prefers BU_CDP_WS; an empty BU_BROWSER_ID means no cloud browser.
  export BU_CDP_WS="ws://127.0.0.1:$PORT$WSPATH" BU_CDP_URL="http://127.0.0.1:$PORT" BU_BROWSER_ID=''
  # One Browser Harness daemon per slot. Unnamed, every run would share the "default" daemon and drive
  # whichever Chrome that daemon attached to first.
  export BU_NAME="jev-$SLOT"
  NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
  no_proxy="127.0.0.1,localhost${no_proxy:+,$no_proxy}"
  export NO_PROXY no_proxy
  if [ "${JEV_TEXT:-}" != 1 ]; then
    exec uv run --frozen --env-file .env python examples/run.py --url="$2" --goal="$3"
  fi

  # JEV_TEXT=1: jev-text.py runs the same runner and reads the page text just before Jev closes its tab. It
  # signals the launcher when the task is over, so the read has its own 10 s instead of counting against
  # JEV_TIMEOUT. The text is printed only after a finished run (exit 0); a failed read never changes the exit code.
  text="$BH_HOME/page-text-$SLOT"
  rm -f "$text" "$text.err"
  JEV_TEXT_FILE="$text" JEV_TEXT_MAX="${JEV_TEXT_MAX:-20000}" \
    uv run --frozen --env-file .env python jev-text.py examples/run.py --url="$2" --goal="$3"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ -s "$text.err" ]; then
      cat "$text.err" >&2
    elif [ -s "$text" ]; then
      cat "$text"
    else
      echo "jev: could not read page text: nothing was captured" >&2
    fi
  fi
  rm -f "$text" "$text.err"
  exit "$rc"
}

if [ "${1:-}" = __run ] && [ $# -eq 4 ]; then
  case "${JEV_SLOT:-}" in 933[3-9]|9340) run_task "$2" "$3" "$4" ;; esac
  usage
fi

# Stage 1.
case "$#:${1:-}" in 1:--stop|1:--check|2:*) ;; *) usage ;; esac
[ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 1; }
if [ "$1" = --stop ] && [ $# -eq 1 ]; then stop_all; exit $?; fi
mode=task url="${1:-}" goal="${2:-}"
if [ "$1" = --check ] && [ $# -eq 1 ]; then mode=check url=- goal=-; fi
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$HOME/tools/jev-ultrafast" || { echo "Jev is not installed in $HOME/tools/jev-ultrafast: run install.sh"; exit 1; }

# Defaults from launcher.env: read as plain text (never sourced), only the keys above.
conf="$HOME/tools/jev-ultrafast/launcher.env"
if [ -f "$conf" ]; then
  keys=" JEV_CHROME JEV_CHROME_ARGS JEV_TEXT_MODEL JEV_TEXT_MODEL_BASE_URL JEV_TIMEOUT JEV_TEXT JEV_TEXT_MAX "
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
if [ "$mode" = task ] && [ "${JEV_TEXT:-}" = 1 ]; then
  case "${JEV_TEXT_MAX:-20000}" in
    [1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9][0-9])
      [ "${JEV_TEXT_MAX:-20000}" -ge 1000 ] && [ "${JEV_TEXT_MAX:-20000}" -le 200000 ] ;;
    *) false ;;
  esac || { echo "JEV_TEXT_MAX must be a whole number of characters from 1000 to 200000"; exit 2; }
fi

LOCKS="$HOME/tools/.jev-locks"
mkdir -p "$LOCKS" || { echo "cannot create $LOCKS"; exit 1; }

# Perl takes the first free slot with a kernel lock (flock) and holds it for the whole run. The kernel drops the
# lock when the last holder exits, however it exits, so a crashed run never leaves a stale lock. The holders are
# this process and stage 2's watcher, so a slot stays locked until its task group is gone.
# The task runs as stage 2 in its own process group; on timeout, SIGINT, SIGTERM or SIGHUP the whole group is
# killed (macOS has no `timeout`). The guard pipe's write end stays here, so the group also dies if this process
# is killed outright. Either way this process exits only after the group is gone.
exec perl -MFcntl=:DEFAULT,:flock -MPOSIX=SIGHUP,SIGINT,SIGTERM,SIGUSR1,SIG_BLOCK,SIG_UNBLOCK,sigprocmask -e '
  my ($locks, $t, $self, $mode, $url, $goal) = @ARGV;
  my ($lock, $slot);
  for my $s (9333 .. 9340) {
    sysopen(my $fh, "$locks/$s.lock", O_RDWR | O_CREAT, 0600)
      or do { print "cannot open $locks/$s.lock: $!\n"; exit 1 };
    if (flock($fh, LOCK_EX | LOCK_NB)) { ($lock, $slot) = ($fh, $s); last }
    unless ($!{EWOULDBLOCK} || $!{EAGAIN}) { print "cannot lock $locks/$s.lock: $!\n"; exit 1 }
    close $fh;
  }
  unless ($lock) { print "all 8 Jev slots busy\n"; exit 75 }
  $ENV{JEV_SLOT} = $slot;
  $ENV{JEV_LAUNCHER_PID} = $$;
  pipe(my $guard_r, my $guard_w) or do { print "pipe failed: $!\n"; exit 1 };

  # Hold the signals until the child has its own process group and the handlers are set.
  my $sigs = POSIX::SigSet->new(SIGHUP, SIGINT, SIGTERM, SIGUSR1);
  sigprocmask(SIG_BLOCK, $sigs);
  my $pid = fork;
  unless (defined $pid) { print "fork failed: $!\n"; exit 1 }
  unless ($pid) {
    setpgrp(0, 0);
    close $guard_w;
    # Stage 2 gets the guard pipe as fd 9 and the lock as fd 8, both kept open across exec. Copy them above 9
    # first so neither can overwrite the other.
    my $g = fcntl($guard_r, F_DUPFD, 10) or POSIX::_exit(1);
    my $l = fcntl($lock, F_DUPFD, 10) or POSIX::_exit(1);
    defined POSIX::dup2($g, 9) or POSIX::_exit(1);
    defined POSIX::dup2($l, 8) or POSIX::_exit(1);
    POSIX::close($g); POSIX::close($l);
    my @keep;    # handles must stay alive until exec, or perl closes the fds
    for my $n (8, 9) { open(my $h, "<&=", $n) or POSIX::_exit(1); fcntl($h, F_SETFD, 0) or POSIX::_exit(1); push @keep, $h }
    sigprocmask(SIG_UNBLOCK, $sigs);
    exec("bash", $self, "__run", $mode, $url, $goal) or do { print STDERR "exec failed: $!\n"; POSIX::_exit(1) };
  }
  close $guard_r;
  setpgrp($pid, $pid);
  sub group_gone { for (1 .. 60) { return unless kill 0, -$pid; select(undef, undef, undef, 0.05) } }
  sub stop {
    my ($code, $wait) = @_;
    kill "TERM", -$pid; sleep $wait; kill "KILL", -$pid;
    waitpid($pid, 0); group_gone(); exit $code;
  }
  $SIG{ALRM} = sub { print STDERR "jev: stopped after ${t}s\n"; stop(124, 2) };
  $SIG{HUP}  = sub { stop(129, 1) };
  $SIG{INT}  = sub { stop(130, 1) };
  $SIG{TERM} = sub { stop(143, 1) };
  # JEV_TEXT=1: the task is over and the page text is being read; give that at least 15 s (it caps itself at 10).
  $SIG{USR1} = sub { my $left = alarm 0; alarm($left > 15 ? $left : 15) };
  sigprocmask(SIG_UNBLOCK, $sigs);
  alarm $t;
  waitpid($pid, 0);
  my $status = $?;
  alarm 0;
  close $guard_w;    # wakes the watcher, which ends the group
  group_gone();
  exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
' "$LOCKS" "$timeout" "$self" "$mode" "$url" "$goal"
