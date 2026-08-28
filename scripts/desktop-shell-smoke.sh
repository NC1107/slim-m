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
# settled geometry polls rather than asserting once. The splash-size checks
# below sample continuously from launch and keep every distinct size seen
# rather than reading geometry at one specific poll: a bootstrap fast enough
# to beat one poll (observed both on an unrelated PR and on a release commit,
# see the incident notes this PR's description links) used to read as the
# splash never having appeared, when it plainly had. This still cannot rule
# out a bootstrap so fast it beats the 100ms sample interval itself - that
# residual race is real, just far smaller than racing a single poll - and it
# still asserts the same claim decision 0012 makes (a real splash size, then
# a real settle), only at whatever instant it actually happened rather than
# at one guessed instant.
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
readonly SPLASH_WIDTH=380
readonly SPLASH_HEIGHT=460
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

window_id() {
  # track_to_settled_size assigns this bare, so a "not listed yet" grep miss during a hide must not trip set -e via pipefail.
  wmctrl -l | grep "$APP_NAME" | head -1 | awk '{print $1}' || true
}

current_size() {
  local id actual w h
  id="$(window_id)"
  [[ -n "$id" ]] || return 1
  actual="$(xdotool getwindowgeometry --shell "$id" 2>/dev/null)" || return 1
  w="$(echo "$actual" | sed -n 's/^WIDTH=//p')"
  h="$(echo "$actual" | sed -n 's/^HEIGHT=//p')"
  [[ -n "$w" && -n "$h" ]] || return 1
  echo "${w}x${h}"
}

# SIZES accumulates every distinct size seen so far, oldest first, and is reset at the start of each track_to_settled_size call.
SIZES=()

# A bare SIZES[-1] throws under set -e when SIZES has zero elements, not just an unset value, so every read of the last entry goes through this instead.
last_size() {
  [[ ${#SIZES[@]} -gt 0 ]] && echo "${SIZES[-1]}"
}

record_size() {
  local size
  size="$(current_size)" || return 0
  if [[ "$(last_size)" != "$size" ]]; then
    SIZES+=("$size")
  fi
}

# Samples every 0.1s until the size reads settled for three straight samples; see the header comment for why this replaced a single existence-then-geometry check.
track_to_settled_size() {
  local expected_width="$1" expected_height="$2" timeout_s="$3"
  local expected="${expected_width}x${expected_height}" waited=0 hits=0
  SIZES=()
  while true; do
    record_size
    if [[ "$(last_size)" == "$expected" ]]; then
      hits=$((hits + 1))
      [[ "$hits" -ge 3 ]] && return 0
    else
      hits=0
    fi
    sleep 0.1
    waited=$((waited + 1))
    if [[ "$waited" -ge "$((timeout_s * 10))" ]]; then
      if [[ ${#SIZES[@]} -eq 0 ]]; then
        echo "::error::window titled slim-m did not appear within ${timeout_s}s" >&2
      else
        echo "::error::window never settled at ${expected} within ${timeout_s}s (observed sequence: ${SIZES[*]})" >&2
      fi
      exit 1
    fi
  done
}

assert_splash_seen() {
  local size
  for size in "${SIZES[@]}"; do
    [[ "$size" == "${SPLASH_WIDTH}x${SPLASH_HEIGHT}" ]] && return 0
  done
  echo "::error::window never passed through the splash size ${SPLASH_WIDTH}x${SPLASH_HEIGHT}; observed sequence: ${SIZES[*]:-none}" >&2
  exit 1
}

echo "::group::fresh launch starts in the small splash shape, then settles into the documented default size"
"$BIN" &
APP_PID=$!
track_to_settled_size 1280 720 50
assert_splash_seen
echo "observed size sequence: ${SIZES[*]}"
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
track_to_settled_size 900 650 50
assert_splash_seen
echo "observed size sequence: ${SIZES[*]}"
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
