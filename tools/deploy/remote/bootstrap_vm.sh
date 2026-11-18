#!/usr/bin/env bash
# One-time VM preparation (run as root on the Oracle VM, Ubuntu or Oracle Linux): user, directories, unit, env template, OS firewall for UDP.
set -euo pipefail
PORT="${PORT:-2456}"
here="$(cd "$(dirname "$0")" && pwd)"
id peepeechess >/dev/null 2>&1 || useradd --system --home /var/lib/peepeechess --shell /usr/sbin/nologin peepeechess
mkdir -p /opt/peepeechess/releases /etc/peepeechess /var/lib/peepeechess
chown peepeechess:peepeechess /var/lib/peepeechess
install -m 644 "$here/../systemd/peepeechess-server.service" /etc/systemd/system/peepeechess-server.service
[ -f /etc/peepeechess/server.env ] || install -m 600 "$here/../systemd/server.env.example" /etc/peepeechess/server.env
if command -v ufw >/dev/null 2>&1; then ufw allow "$PORT/udp" || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PORT/udp" && firewall-cmd --reload || true
fi
systemctl daemon-reload
echo "Edit /etc/peepeechess/server.env, add the DTLS certificate and key, then deploy a release."
echo "Also open UDP $PORT in the OCI security list / network security group."
