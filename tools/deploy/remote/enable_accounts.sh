#!/usr/bin/env bash
# Turns accounts ON (or OFF with --off) for the game server. ON: the game server reports results to the local account service and from then on ONLY
# accepts players who logged in (an anonymous room-code client is refused: "An account matchmaking ticket is required"). HTTPS starts via Caddy.
#   sudo enable_accounts.sh --api-only  # sign-in/profile/friends only; anonymous room-code play keeps working (do this first)
#   sudo enable_accounts.sh        # full: also route the game server through accounts (anonymous play is then closed)
#   sudo enable_accounts.sh --off  # back to anonymous room-code play
set -euo pipefail
ENV=/etc/peepeechess/server.env
set_var() { grep -q "^$1=" "$ENV" && sed -i "s|^$1=.*|$1=$2|" "$ENV" || echo "$1=$2" >> "$ENV"; }
if [ "${1:-}" = "--api-only" ]; then
  # Sign-in, profile, friends, history and leaderboards over HTTPS; the game server is NOT touched, so anonymous room-code play keeps working.
  systemctl is-active --quiet peepeechess-accounts || { echo "the account service is not running: install a release first (install_accounts_release.sh)" >&2; exit 2; }
  systemctl enable --now caddy
  echo "account API ON (game server unchanged). URL: https://$(cat /etc/peepeechess/accounts.domain)   (Caddy needs ~30 s for its certificate the first time)"
  echo "check: curl https://$(cat /etc/peepeechess/accounts.domain)/health"
  exit 0
fi
if [ "${1:-}" = "--off" ]; then
  set_var EXTRA_ARGS ""; sed -i '/^PEEPEECHESS_BACKEND_SECRET=/d' "$ENV"
  systemctl restart peepeechess-server; systemctl stop caddy 2>/dev/null || true
  echo "accounts OFF: the game server accepts anonymous room-code play again"; exit 0
fi
systemctl is-active --quiet peepeechess-accounts || { echo "the account service is not running: install a release first (install_accounts_release.sh)" >&2; exit 2; }
SECRET="$(grep -E '^NATIVE_SERVER_SECRET=' /etc/peepeechess/accounts.env | cut -d= -f2-)"; [ -n "$SECRET" ] || { echo "no secret in accounts.env" >&2; exit 2; }
SERVER_ID="$(grep -E '^NATIVE_SERVER_ID=' /etc/peepeechess/accounts.env | cut -d= -f2)"; PORT_NUMBER="$(grep -E '^NATIVE_API_PORT=' /etc/peepeechess/accounts.env | cut -d= -f2)"
set_var EXTRA_ARGS "--backend-url=http://127.0.0.1:${PORT_NUMBER:-8787} --backend-insecure-local --server-id=${SERVER_ID:-vps-1} --outbox-dir=/var/lib/peepeechess/outbox"
set_var PEEPEECHESS_BACKEND_SECRET "$SECRET"
mkdir -p /var/lib/peepeechess/outbox && chown peepeechess:peepeechess /var/lib/peepeechess/outbox
systemctl enable --now caddy; systemctl restart peepeechess-server
sleep 3; systemctl is-active --quiet peepeechess-server && echo "game server restarted with accounts ON" || { echo "game server did not start: journalctl -u peepeechess-server" >&2; exit 1; }
echo "account URL: https://$(cat /etc/peepeechess/accounts.domain)   (check: curl https://$(cat /etc/peepeechess/accounts.domain)/health; Caddy needs ~30 s to get its certificate the first time)"
