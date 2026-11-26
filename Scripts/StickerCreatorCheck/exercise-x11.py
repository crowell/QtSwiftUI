"""Run under xvfb-run as an unprivileged user with the UI, decoder, image and screenshot paths."""
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys

app, decoder, image, output = map(os.path.abspath, sys.argv[1:])
client, worker = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
children = set()

def start(binary, endpoint, env, output_fd=None):
    actions = [(os.POSIX_SPAWN_DUP2, endpoint.fileno(), 160)]
    if output_fd is not None:
        actions.append((os.POSIX_SPAWN_DUP2, output_fd, 1))
    pid = os.posix_spawn(binary, [binary], env, file_actions=actions)
    children.add(pid)
    return pid

def xdo(*args):
    return subprocess.check_output(["xdotool", *args], text=True, timeout=5).strip()

try:
    start(decoder, worker, dict(os.environ, LD_LIBRARY_PATH="/usr/local/lib/serein/workers"))
    read_fd, write_fd = os.pipe()
    pid = start(app, client, dict(os.environ, QTSWIFTUI_SCREENSHOT=output, QTSWIFTUI_CAPTURE_DELAY_MS="7500"), write_fd)
    os.close(write_fd)
    worker.close()
    client.close()
    window = xdo("search", "--sync", "--onlyvisible", "--pid", str(pid)).splitlines()[0]
    xdo("windowfocus", "--sync", window)
    xdo("mousemove", "--window", window, "157", "286", "click", "1")
    dialog = xdo("search", "--sync", "--onlyvisible", "--name", "^Open$").splitlines()[-1]
    xdo("windowfocus", "--sync", dialog)
    xdo("key", "ctrl+l")
    xdo("type", "--clearmodifiers", image)
    xdo("key", "Return")
    _, status = os.waitpid(pid, 0)
    children.remove(pid)
    with os.fdopen(read_fd) as diagnostics:
        decoded = diagnostics.read()
    if status or "Decoded sticker " not in decoded or not Path(output).is_file():
        raise RuntimeError("The creator did not capture the selected image")
finally:
    for pid in children:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
