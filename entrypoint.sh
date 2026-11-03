#!/bin/bash
set -euo pipefail

PUID=${PUID:-1000}
PGID=${PGID:-1000}
PORT=${ORCA_PORT:-6768}
ADDR=${ORCA_PAIRING_ADDRESS:-}

# Match the NAS folder owner so files in /workspace stay editable from DSM
if [ "$(id -u)" = 0 ] && [ -z "${ORCA_AS_USER:-}" ]; then
  if [ "$PUID" = 0 ]; then echo "[orca] PUID=0 is not allowed; use your NAS user's uid." >&2; exit 1; fi
  if [ "$(id -g orca)" != "$PGID" ]; then groupmod -o -g "$PGID" orca; fi
  if [ "$(id -u orca)" != "$PUID" ]; then usermod -o -u "$PUID" orca; fi
  chown orca:orca /home/orca /workspace
  chmod u+rwx /home/orca /workspace
  # Synology shared folders often carry ACLs that still block the owner; fail loudly instead of crash-looping
  for d in /home/orca /workspace; do
    if ! runuser -u orca -- test -w "$d"; then
      echo "[orca] $d is not writable by uid=$PUID gid=$PGID." >&2
      ls -ldn "$d" >&2
      echo "[orca] Fix on the NAS (SSH): sudo synoacltool -del <folder>; sudo chown -R $PUID:$PGID <folder>; sudo chmod -R u+rwX <folder>" >&2
      sleep 300; exit 1
    fi
  done
  # A stale X lock from a previous container run blocks Xvfb
  rm -f /tmp/.X*-lock
  exec runuser -u orca -- env ORCA_AS_USER=1 "$0" "$@"
fi

export HOME=/home/orca
cd /workspace

if [ -z "$ADDR" ]; then
  echo "[orca] ORCA_PAIRING_ADDRESS is empty. Set it to the NAS Tailscale IP (100.x.y.z)." >&2
  exit 1
fi

args=(serve --port "$PORT" --pairing-address "$ADDR")
case "${ORCA_PAIRING_MODE:-desktop}" in
  mobile) args+=(--mobile-pairing) ;;   # print QR/link for the Orca mobile app
  off)    args+=(--no-pairing) ;;       # normal operation once everything is paired
  *)      ;;                            # desktop: print link for PC "Add Server"
esac

# AI 팀 회의실 web page (restarts itself if it crashes)
if [ "${MEETING_ROOM:-on}" != off ]; then
  mkdir -p "$HOME/meeting-room"
  [ -f "$HOME/meeting-room/roles.json" ] || cp /opt/meeting-room/roles.json "$HOME/meeting-room/roles.json"
  export MEETING_ROOM_ROLES="$HOME/meeting-room/roles.json"
  ( sleep 5; while true; do node /opt/meeting-room/server.mjs; echo "[meeting-room] stopped, restarting in 5s" >&2; sleep 5; done ) &
fi

echo "[orca] starting: orca-ide ${args[*]}"
exec orca-ide "${args[@]}"
