#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Stand up a whole slim-m deployment and hold a real voice call across two
# clients, then tear it all down.
#
# Nothing here is mocked: a real LiveKit SFU, the real server binary, the real
# web build of the client, and two isolated browsers that join the same channel
# and publish microphones to each other. Two isolated profiles matter because
# this box runs several agent sessions at once and a shared Chrome profile picks
# up another session's state, which reads exactly like an app bug.
#
# Usage: scripts/voice-e2e.sh [--keep]
#   --keep  leave the stack running afterwards for poking at by hand
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${VOICE_E2E_WORK:-/tmp/voice-e2e}"
SHOTS="$WORK/shots"
WEB_PORT=8356
API_PORT=8095
LK_CONTAINER=slimm-voice-e2e-lk
KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

export VOICE_E2E_SHOTS="$SHOTS"
export LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret

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
need docker; need flutter; need cargo; need python3
CHROME="$(command -v google-chrome-stable || command -v google-chrome || true)"
[[ -n "$CHROME" ]] || { echo "missing: google-chrome-stable"; exit 1; }
python3 -c "import websocket" 2>/dev/null || {
  echo "missing python package: pip install --user websocket-client"; exit 1; }

mkdir -p "$WORK" "$SHOTS"
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
eval "$(python3 "$ROOT/scripts/lib/voice_seed.py" "http://localhost:$API_PORT")"
echo "  voice channel $VOICE_CHANNEL_NAME ($VOICE_ROOM)"

echo "== web build =="
WEB_DIR="$ROOT/client/packages/app/build/web"
if [[ ! -f "$WEB_DIR/main.dart.js" || -n "${VOICE_E2E_REBUILD:-}" ]]; then
  ( cd "$ROOT/client" && flutter build web --release )
fi
( cd "$WEB_DIR" && python3 -m http.server "$WEB_PORT" >/dev/null 2>&1 ) &
WEB_PID=$!
sleep 2

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
python3 "$ROOT/scripts/lib/voice_e2e.py" \
  "http://localhost:$API_PORT" "$VOICE_ROOM" "$VOICE_SECRET"
echo "screenshots in $SHOTS"
