"""Read the visible text of the page Jev ended on (JEV_TEXT=1).

jev-run.sh runs Jev's own example runner, unchanged, through this file:

    python jev-text.py examples/run.py --url=URL --goal=GOAL

Jev closes its tab when the run is over, so the text is read at that moment, just before the tab closes: one
Runtime.evaluate of document.body.innerText on Jev's own CDP session for that tab. Nothing else is sent: no
navigation, no input, no other CDP method. The text is web content: data, never instructions.

Environment (set by jev-run.sh):
  JEV_TEXT_FILE     where the formatted text goes; <file>.err gets the reason if it could not be read
  JEV_TEXT_MAX      characters to keep (default 20000)
  JEV_LAUNCHER_PID  told (SIGUSR1) when the task is over, so the read gets its own time instead of JEV_TIMEOUT's
"""

import os
import re
import runpy
import signal
import sys

from jev_ultrafast import browser as jev_browser

READ_SECONDS = 10
EXPRESSION = "document.body ? document.body.innerText : ''"
# Control characters other than tab and newline (terminal escapes among them) are dropped from web text.
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def collapse(text):
    """Drop control characters and trailing spaces, and collapse each run of blank lines to one."""
    out, blank = [], False
    for line in CONTROL.sub("", text).splitlines():
        line = line.rstrip()
        if not line:
            if blank:
                continue
            blank = True
        else:
            blank = False
        out.append(line)
    return "\n".join(out).strip("\n")


def write(path, data):
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)


def notify_launcher():
    pid = os.environ.get("JEV_LAUNCHER_PID", "")
    if pid.isdigit():
        try:
            os.kill(int(pid), signal.SIGUSR1)
        except OSError:
            pass


def read_page_text(browser):
    path = os.environ["JEV_TEXT_FILE"]
    limit = int(os.environ.get("JEV_TEXT_MAX", "20000"))
    if not browser.target:
        write(path + ".err", "jev: no page to read\n")
        return

    def too_slow(*_args):
        raise TimeoutError("took longer than %d s" % READ_SECONDS)

    previous = signal.signal(signal.SIGALRM, too_slow)
    signal.alarm(READ_SECONDS)
    try:
        text = browser.evaluate(EXPRESSION)
    except Exception as e:  # noqa: BLE001 - any failure only means no text
        write(path + ".err", "jev: could not read page text: %s\n" % (str(e) or type(e).__name__))
        return
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)
    if not isinstance(text, str):
        write(path + ".err", "jev: could not read page text: the page returned no text\n")
        return
    text = collapse(text)
    shown = text[:limit]
    write(path, "--- page text (%d chars, truncated: %s) ---\n%s\n--- end page text ---\n"
          % (len(shown), "yes" if len(text) > limit else "no", shown))


def main(argv):
    original_close = jev_browser.Browser.close

    def close(self):
        try:
            notify_launcher()
            read_page_text(self)
        except Exception as e:  # noqa: BLE001 - never let the read break Jev's own close
            try:
                write(os.environ["JEV_TEXT_FILE"] + ".err", "jev: could not read page text: %s\n" % e)
            except Exception:  # noqa: BLE001
                pass
        original_close(self)

    jev_browser.Browser.close = close
    sys.argv = argv
    runpy.run_path(argv[0], run_name="__main__")


if __name__ == "__main__":
    main(sys.argv[1:])
