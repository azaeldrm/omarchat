"""Drive one Omarchat session and print its events, for the live tests.

    python3 -I converse.py <timeout-seconds> <command> [args...] -- <message>...

Runs the command (a backend `session`, or bin/omarchat-session), sends each
message as {"text": ...}, and waits for that turn's "done" event. Prints one
JSON object per line: every event the session emitted, tagged with the turn
it belongs to, then {"turn": n, "type": "turn_end", "seconds": ...}. Anything
the session wrote to stderr comes last as {"type": "stderr", "text": ...}.
Exits 3 when a turn doesn't finish in time.
"""

import json
import subprocess
import sys
import threading
import time


def main() -> int:
    timeout = float(sys.argv[1])
    split = sys.argv.index("--")
    command, messages = sys.argv[2:split], sys.argv[split + 1:]

    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, cwd="/tmp")
    stderr = []
    threading.Thread(target=lambda: stderr.append(proc.stderr.read().decode(errors="replace")),
                     daemon=True).start()

    status = 0
    for turn, message in enumerate(messages, 1):
        started = time.monotonic()
        proc.stdin.write((json.dumps({"text": message}) + "\n").encode())
        proc.stdin.flush()

        finished = threading.Event()

        def read_turn() -> None:
            for raw in proc.stdout:
                try:
                    event = json.loads(raw)
                except json.JSONDecodeError:
                    event = {"type": "garbage", "text": raw.decode(errors="replace").strip()}
                print(json.dumps({"turn": turn, **event}), flush=True)
                if event.get("type") == "done":
                    finished.set()
                    return
            finished.set()

        reader = threading.Thread(target=read_turn, daemon=True)
        reader.start()
        if not finished.wait(timeout):
            status = 3
        print(json.dumps({"turn": turn, "type": "turn_end", "seconds": round(time.monotonic() - started, 1)}),
              flush=True)
        if status:
            break

    proc.stdin.close()
    try:
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
    time.sleep(0.2)
    if stderr and stderr[0].strip():
        print(json.dumps({"type": "stderr", "text": stderr[0].strip()[-2000:]}), flush=True)
    return status


if __name__ == "__main__":
    sys.exit(main())
