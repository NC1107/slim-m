#!/usr/bin/env bash
# Drives the built Linux release bundle under Xvfb (a virtual, off-screen X
# server on a CI runner - never this developer's own display) and checks
# decision 0012's own claims: the window appears at the small splash size,
# settles into the documented default once bootstrap hands off, a saved
# geometry changes the next launch's settled size, a close request no longer
# terminates the process, a second launch hands off to the first rather than
# spawning its own window, and - see below - a real quit still exists and
# works even though this bus has no tray host at all. See
# docs/decisions/0012-desktop-window-shell.md for what this can and cannot
# prove; the caller must run this under a real D-Bus session bus (see
# client-ci.yml's dbus-run-session wrapper) or the last two checks below are
# meaningless, since GApplication's own single-instance activation needs one.
#
# The window appears at DesktopWindowShell.splashWindowSize (380x460) before
# bootstrap finishes, then DesktopWindowShell.prepareHandoff hides it, applies
# the real geometry, and DesktopWindowShell.revealAfterHandoff shows it again -
# see that decision record's superseding section. wmctrl briefly stops
# listing the window during that hide, so every check below that needs the
# settled geometry polls rather than asserting once.
#
# There is no org.kde.StatusNotifierWatcher on this bus - fluxbox is a plain
# window manager, not a full desktop shell - so the close path here always
# takes the minimizeToTaskbar fallback, never hideToTray. The final close
# assertion checks the window is still listed by wmctrl after close, not only
# that the process is still alive: both branches leave the process running,
# so liveness alone cannot tell a correct fallback from a wrongly hidden,
# unreachable window. That also makes this the one job that structurally
# takes the no-tray path on every run, which is exactly the path a real quit
# had gone missing on: the only "Quit slim-m" anywhere used to live in the
# tray menu, and that menu is never rendered with no host to display it. The
# final group below drives Ctrl+Q - a real key event, not a semantics-tree
# interaction this harness has no accessibility bridge to drive - and checks
# the process actually exits, closing the loop this file's own close-request
# group deliberately leaves open (the window staying reachable, not quit).
set -euo pipefail

readonly APP_NAME="slim-m"
BUNDLE="${1:?usage: desktop-shell-smoke.sh <bundle-dir>}"
BIN="${BUNDLE}/slimm_app"
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1
STATE_DIR="$(mktemp -d)"
export HOME="${STATE_DIR}/home"
export XDG_CONFIG_HOME="${STATE_DIR}/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

Xvfb "$DISPLAY" -screen 0 1920x1080x24 &
XVFB_PID=$!

wait_for_x_socket() {
  local timeout_s="$1" waited=0
  while [[ ! -S "/tmp/.X11-unix/X${DISPLAY#:}" ]]; do
    sleep 0.2
    waited=$((waited + 1))
    if [[ "$waited" -ge "$((timeout_s * 5))" ]]; then
      echo "::error::Xvfb never opened its socket within ${timeout_s}s" >&2
      exit 1
    fi
  done
}
wait_for_x_socket 10

fluxbox &
FLUXBOX_PID=$!
sleep 1

cleanup() {
  kill "${APP_PID:-0}" 2>/dev/null || true
  kill "$FLUXBOX_PID" 2>/dev/null || true
  # Letting fluxbox actually exit before Xvfb goes quiets its own XIOError.
  wait "$FLUXBOX_PID" 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_window() {
  local timeout_s="$1" waited=0
  while ! wmctrl -l | grep -q "$APP_NAME"; do
    sleep 0.5
    waited=$((waited + 1))
    if [[ "$waited" -ge "$((timeout_s * 2))" ]]; then
      echo "::error::window titled slim-m did not appear within ${timeout_s}s" >&2
      exit 1
    fi
  done
}

window_id() {
  # wait_for_geometry assigns this bare, so a "not listed yet" grep miss during a hide must not trip set -e via pipefail.
  wmctrl -l | grep "$APP_NAME" | head -1 | awk '{print $1}' || true
}

assert_geometry() {
  local expected_width="$1" expected_height="$2" actual
  actual="$(xdotool getwindowgeometry --shell "$(window_id)")"
  echo "$actual"
  echo "$actual" | grep -q "^WIDTH=${expected_width}\$"
  echo "$actual" | grep -q "^HEIGHT=${expected_height}\$"
}

# Polls rather than asserting once: prepareHandoff hides the window while it
# applies the real geometry, so window_id/xdotool can see nothing at all for
# part of this wait, and a single immediate check would be racing that hide.
wait_for_geometry() {
  local expected_width="$1" expected_height="$2" timeout_s="$3"
  local waited=0 id actual=""
  while true; do
    id="$(window_id)"
    if [[ -n "$id" ]]; then
      actual="$(xdotool getwindowgeometry --shell "$id" 2>/dev/null || true)"
      if echo "$actual" | grep -q "^WIDTH=${expected_width}\$" && echo "$actual" | grep -q "^HEIGHT=${expected_height}\$"; then
        echo "$actual"
        return 0
      fi
    fi
    sleep 0.5
    waited=$((waited + 1))
    if [[ "$waited" -ge "$((timeout_s * 2))" ]]; then
      echo "::error::window never settled at ${expected_width}x${expected_height} within ${timeout_s}s (last seen: ${actual:-nothing})" >&2
      exit 1
    fi
  done
}

echo "::group::fresh launch starts in the small splash shape, then settles into the documented default size"
"$BIN" &
APP_PID=$!
wait_for_window 30
# 380x460 must match DesktopWindowShell.splashWindowSize.
assert_geometry 380 460
wait_for_geometry 1280 720 20
echo "::endgroup::"

echo "::group::resize past the debounce, then kill mid-session"
xdotool windowsize "$(window_id)" 900 650
# A 500ms debounce plus a disk write; 1s flaked on a loaded runner, see PR #580.
sleep 3
kill -9 "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
echo "::endgroup::"

echo "::group::relaunch starts in the splash shape again, then settles into the geometry saved mid-session, not the default"
"$BIN" &
APP_PID=$!
wait_for_window 30
assert_geometry 380 460
wait_for_geometry 900 650 20
echo "::endgroup::"

echo "::group::a close request no longer terminates the process, and the window stays reachable"
sleep 3
wmctrl -c "$APP_NAME"
sleep 3
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "::error::the process exited after a close request; setPreventClose did not intercept it" >&2
  exit 1
fi
if ! wmctrl -l | grep -q "$APP_NAME"; then
  echo "::error::the window is unreachable after close; that is hideToTray with no tray, not minimizeToTaskbar" >&2
  exit 1
fi
echo "process still running and its window still reachable after close, as decision 0012's fallback expects"
echo "::endgroup::"

echo "::group::a second launch hands off to the first process instead of spawning a new one"
"$BIN" &
SECOND_PID=$!
waited=0
while kill -0 "$SECOND_PID" 2>/dev/null; do
  sleep 0.5
  waited=$((waited + 1))
  if [[ "$waited" -ge 20 ]]; then
    echo "::error::the second launch is still running after 10s; it should hand off to the first process and exit" >&2
    kill -9 "$SECOND_PID" 2>/dev/null || true
    exit 1
  fi
done
sleep 1
window_count="$(wmctrl -l | grep -c "$APP_NAME" || true)"
if [[ "$window_count" -ne 1 ]]; then
  echo "::error::expected exactly one slim-m window after a second launch, found ${window_count}" >&2
  wmctrl -l
  exit 1
fi
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "::error::the original process exited; a second launch should focus it, not replace it" >&2
  exit 1
fi
echo "the second launch exited after handing off, exactly one window remains, and it is still the original process's"
echo "::endgroup::"

echo "::group::Ctrl+Q quits for real, with no tray host reachable on this bus at all"
xdotool windowactivate "$(window_id)"
sleep 1
xdotool key --clearmodifiers ctrl+q
waited=0
while kill -0 "$APP_PID" 2>/dev/null; do
  sleep 0.5
  waited=$((waited + 1))
  if [[ "$waited" -ge 20 ]]; then
    echo "::error::the process is still running 10s after Ctrl+Q; there is still no way to quit with no tray" >&2
    exit 1
  fi
done
echo "Ctrl+Q ended the process - a real quit path with no tray menu to hold the only one"
echo "::endgroup::"
