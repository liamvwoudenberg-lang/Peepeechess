#!/usr/bin/env bash
# Runs ON the Oracle VM (as root, via sudo). Installs one server package, restarts the service, health-checks it and rolls back on failure.
#   sudo install_release.sh /tmp/peepeechess-server-<arch>-<sha>.tar.gz
# Layout: /opt/peepeechess/releases/<name>/  and  /opt/peepeechess/current -> active release (the last 3 are kept for rollback).
set -euo pipefail
PKG="${1:?usage: install_release.sh <package.tar.gz>}"
BASE=/opt/peepeechess
SERVICE=peepeechess-server
KEEP=3
PORT_NUMBER="$(grep -E '^PORT=' /etc/peepeechess/server.env 2>/dev/null | cut -d= -f2 || true)"
PORT_NUMBER="${PORT_NUMBER:-2456}"
if [ -f "$PKG.sha256" ]; then (cd "$(dirname "$PKG")" && sha256sum -c "$(basename "$PKG").sha256"); fi
NAME="$(basename "$PKG" .tar.gz)"
mkdir -p "$BASE/releases" /var/lib/peepeechess
id peepeechess >/dev/null 2>&1 || useradd --system --home /var/lib/peepeechess --shell /usr/sbin/nologin peepeechess
chown peepeechess:peepeechess /var/lib/peepeechess
rm -rf "${BASE:?}/releases/$NAME"
mkdir "$BASE/releases/$NAME"
tar -xzf "$PKG" -C "$BASE/releases/$NAME"
chmod +x "$BASE/releases/$NAME/peepeechess-server" "$BASE/releases/$NAME/run-server.sh"
PREVIOUS="$(readlink -f "$BASE/current" 2>/dev/null || true)"

point_current_at() {
  ln -sfn "$1" "$BASE/current.new"
  mv -T "$BASE/current.new" "$BASE/current"
}

healthy() {
  systemctl is-active --quiet "$SERVICE" || return 1
  for _ in $(seq 1 20); do
    if journalctl -u "$SERVICE" --since "-60s" --no-pager 2>/dev/null | grep -q "SERVER_READY protocol=peepeechess-enet-v1" && ss -lun | grep -q ":${PORT_NUMBER} "; then
      return 0
    fi
    sleep 1
  done
  return 1
}

point_current_at "$BASE/releases/$NAME"
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null 2>&1 || true
systemctl restart "$SERVICE"
if healthy; then
  echo "DEPLOYED $NAME"
  cat "$BASE/current/VERSION"
  ls -1dt "$BASE"/releases/* | tail -n +$((KEEP + 1)) | xargs -r rm -rf
  exit 0
fi
echo "HEALTH CHECK FAILED for $NAME" >&2
journalctl -u "$SERVICE" --no-pager -n 30 >&2 || true
if [ -n "$PREVIOUS" ] && [ -d "$PREVIOUS" ] && [ "$PREVIOUS" != "$BASE/releases/$NAME" ]; then
  point_current_at "$PREVIOUS"
  systemctl restart "$SERVICE"
  if healthy; then echo "ROLLED BACK to $(basename "$PREVIOUS")" >&2; else echo "ROLLBACK ALSO UNHEALTHY" >&2; fi
else
  echo "no previous release to roll back to" >&2
fi
exit 1
