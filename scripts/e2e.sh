#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Stand up a whole slim-m deployment and drive two clients through the product,
# then tear it all down.
#
# Nothing here is mocked: a real LiveKit SFU, the real server binary, the real
# web build of the client, and two isolated browsers that join the same channel
# and publish microphones to each other. Two isolated profiles matter because
# this box runs several agent sessions at once and a shared Chrome profile picks
# up another session's state, which reads exactly like an app bug.
#
# Usage: scripts/e2e.sh [--keep]
#   --keep  leave the stack running afterwards for poking at by hand
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${E2E_WORK:-/tmp/e2e}"
SHOTS="$WORK/shots"
WEB_PORT=8356
API_PORT=8095
LK_CONTAINER=slimm-e2e-lk
KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

# What was actually built, since a stale tree passes and reads as thorough.
say_commit() {
  local head behind
  head="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "e2e: building from $head"
  git -C "$ROOT" rev-parse --verify -q origin/main >/dev/null || return 0
  behind="$(git -C "$ROOT" rev-list --count "HEAD..origin/main" 2>/dev/null || echo 0)"
  [[ "$behind" == "0" ]] || echo "e2e: WARNING this tree is $behind commit(s) behind origin/main"
  git -C "$ROOT" diff --quiet 2>/dev/null || echo "e2e: note the working tree has uncommitted changes"
}
say_commit

export E2E_SHOTS="$SHOTS"
export E2E_FIXTURES="$WORK/fixtures"
export E2E_SCHEMA="$ROOT/schema/openapi.yaml"
# LiveKit's own dev-mode pair, for a throwaway container on this machine that
# is torn down with the run. Overridable, so nothing here assumes them.
export LIVEKIT_API_KEY="${LIVEKIT_API_KEY:-devkey}"
export LIVEKIT_API_SECRET="${LIVEKIT_API_SECRET:-secret}"

cleanup() {
  local code=$?
  if [[ $KEEP -eq 1 ]]; then
    echo "--keep: stack left up (web :$WEB_PORT, api :$API_PORT, sfu :7880)"
    return
  fi
  echo "== teardown =="
  [[ -n "${WEB_PID:-}" ]] && kill "$WEB_PID" 2>/dev/null || true
  [[ -n "${API_PID:-}" ]] && kill "$API_PID" 2>/dev/null || true
  pkill -f "remote-debugging-port=980[12]" 2>/dev/null || true
  docker rm -f "$LK_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$WORK/chrome-alice" "$WORK/chrome-bob" "$WORK/slimm.db"*
  exit $code
}
trap cleanup EXIT

need() {
  local tool="$1"
  command -v "$tool" >/dev/null || { echo "missing: $tool"; exit 1; }
}
need docker; need flutter; need cargo; need python3; need curl
CHROME="$(command -v google-chrome-stable || command -v google-chrome || true)"
[[ -n "$CHROME" ]] || { echo "missing: google-chrome-stable"; exit 1; }
python3 -c "import websocket" 2>/dev/null || {
  echo "missing python package: pip install --user websocket-client"; exit 1; }

mkdir -p "$WORK" "$SHOTS" "$WORK/fixtures"
python3 "$ROOT/scripts/lib/e2e_fixtures.py" "$WORK/fixtures"
rm -f "$WORK/slimm.db"*

echo "== SFU =="
docker rm -f "$LK_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$LK_CONTAINER" --rm \
  -p 7880:7880 -p 7881:7881 -p 50000-50050:50000-50050/udp \
  livekit/livekit-server --dev --bind 0.0.0.0 >/dev/null
for _ in $(seq 30); do
  curl -sf http://localhost:7880 >/dev/null 2>&1 && break; sleep 1
done

echo "== server =="
( cd "$ROOT" && SQLX_OFFLINE=true cargo build --release --bin slimm-server -q )
SLIMM_PORT=$API_PORT \
SLIMM_DATABASE_PATH="$WORK/slimm.db" \
SLIMM_CORS_ALLOWED_ORIGINS="http://localhost:$WEB_PORT" \
SLIMM_LIVEKIT_URL=ws://localhost:7880 \
SLIMM_LIVEKIT_API_KEY=$LIVEKIT_API_KEY \
SLIMM_LIVEKIT_API_SECRET=$LIVEKIT_API_SECRET \
  "$ROOT/target/release/slimm-server" > "$WORK/server.log" 2>&1 &
API_PID=$!
for _ in $(seq 60); do
  [[ "$(curl -s http://localhost:$API_PORT/healthz 2>/dev/null)" == "ok" ]] && break
  sleep 1
done
[[ "$(curl -s http://localhost:$API_PORT/healthz)" == "ok" ]] || {
  echo "server never came up:"; tail -20 "$WORK/server.log"; exit 1; }

echo "== accounts and a voice channel =="
eval "$(python3 "$ROOT/scripts/lib/e2e_seed.py" "http://localhost:$API_PORT")"
echo "  voice channel $VOICE_CHANNEL_NAME ($VOICE_ROOM)"

echo "== web build =="
WEB_DIR="$ROOT/client/packages/app/build/web"
# The two gitignored binaries drift needs at runtime; absent, no local database.
bash "$ROOT/client/packages/app/tool/fetch_web_assets.sh"
if [[ ! -f "$WEB_DIR/main.dart.js" || -n "${E2E_REBUILD:-}" ]]; then
  # Flutter copies web/ into build/web once and never re-syncs a new file into it.
  rm -rf "$WEB_DIR"
  ( cd "$ROOT/client/packages/app" && flutter build web --release )
fi

# A server already on this port answers with a build this run did not compile.
if curl -sf -o /dev/null "http://localhost:$WEB_PORT/" 2>/dev/null; then
  echo "port $WEB_PORT is already serving something; stop that first"; exit 1
fi
# Not in a subshell: teardown killed the wrapper and orphaned the server itself.
python3 -m http.server "$WEB_PORT" --directory "$WEB_DIR" >/dev/null 2>&1 &
WEB_PID=$!
# Every file the app reaches for at runtime, not just the ones a build emits.
for asset in main.dart.js flutter_bootstrap.js sqlite3.wasm drift_worker.js; do
  served=0
  for _ in $(seq 20); do
    curl -sf -o /dev/null "http://localhost:$WEB_PORT/$asset" && { served=1; break; }
    sleep 1
  done
  [[ $served -eq 1 ]] || {
    echo "the web build does not serve $asset."
    echo "see client/packages/app/web/README.md; the channel rail and sync both"
    echo "fail with nothing but 'Could not load channels.' when it is missing."
    exit 1; }
done

echo "== two browsers =="
for pair in "9801:alice" "9802:bob"; do
  port="${pair%%:*}"; who="${pair##*:}"
  profile="$WORK/chrome-$who"; rm -rf "$profile"; mkdir -p "$profile"
  # Detached headless Chrome is killed with the launching shell here, so each
  # one is held open by a sleep it outlives.
  nohup setsid bash -c "exec '$CHROME' --headless=new \
    --user-data-dir='$profile' --remote-debugging-port=$port \
    --window-size=1280,900 --no-first-run --no-default-browser-check \
    --use-fake-device-for-media-stream --use-fake-ui-for-media-stream \
    --autoplay-policy=no-user-gesture-required --enable-unsafe-swiftshader \
    --mute-audio \
    --auto-select-desktop-capture-source='Entire screen' \
    'http://localhost:$WEB_PORT'" > "$WORK/chrome-$who.log" 2>&1 < /dev/null &
done
for port in 9801 9802; do
  for _ in $(seq 40); do
    curl -sf "http://127.0.0.1:$port/json/version" >/dev/null 2>&1 && break
    sleep 1
  done
done
sleep 6

echo "== drive =="
python3 -u "$ROOT/scripts/lib/e2e_run.py" \
  "http://localhost:$API_PORT" "$VOICE_ROOM" "$VOICE_SECRET"
echo "screenshots in $SHOTS"
