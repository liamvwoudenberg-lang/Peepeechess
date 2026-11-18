#!/usr/bin/env bash
# Installs one account-service package on the VM (as root): extract, point `current` at it, restart, health-check, roll back on failure. Keeps the last 3.
#   sudo install_accounts_release.sh ~/peepeechess-accounts-<sha>.tar.gz
set -euo pipefail
PKG="${1:?usage: install_accounts_release.sh <package.tar.gz>}"
BASE=/opt/peepeechess-accounts; SERVICE=peepeechess-accounts; KEEP=3
PORT_NUMBER="$(grep -E '^NATIVE_API_PORT=' /etc/peepeechess/accounts.env | cut -d= -f2)"; PORT_NUMBER="${PORT_NUMBER:-8787}"
if [ -f "$PKG.sha256" ]; then (cd "$(dirname "$PKG")" && sha256sum -c "$(basename "$PKG").sha256"); fi
NAME="$(basename "$PKG" .tar.gz)"
rm -rf "${BASE:?}/releases/$NAME"; mkdir -p "$BASE/releases/$NAME"
tar -xzf "$PKG" -C "$BASE/releases/$NAME"; chmod +x "$BASE/releases/$NAME/run-accounts.sh"
PREVIOUS="$(readlink -f "$BASE/current" 2>/dev/null || true)"
point() { ln -sfn "$1" "$BASE/current.new"; mv -T "$BASE/current.new" "$BASE/current"; }
healthy() { for _ in $(seq 1 20); do curl -fsS "http://127.0.0.1:${PORT_NUMBER}/health" 2>/dev/null | grep -q '"ok":true' && return 0; sleep 1; done; return 1; }
point "$BASE/releases/$NAME"; systemctl daemon-reload; systemctl enable "$SERVICE" >/dev/null 2>&1 || true; systemctl restart "$SERVICE"
if healthy; then echo "DEPLOYED $NAME"; cat "$BASE/current/VERSION"; ls -1dt "$BASE"/releases/* | tail -n +$((KEEP + 1)) | xargs -r rm -rf; exit 0; fi
echo "HEALTH CHECK FAILED for $NAME" >&2; journalctl -u "$SERVICE" --no-pager -n 30 >&2 || true
if [ -n "$PREVIOUS" ] && [ -d "$PREVIOUS" ] && [ "$PREVIOUS" != "$BASE/releases/$NAME" ]; then
  point "$PREVIOUS"; systemctl restart "$SERVICE"; if healthy; then echo "ROLLED BACK to $(basename "$PREVIOUS")" >&2; else echo "ROLLBACK ALSO UNHEALTHY" >&2; fi
else echo "no previous release to roll back to" >&2; fi
exit 1
