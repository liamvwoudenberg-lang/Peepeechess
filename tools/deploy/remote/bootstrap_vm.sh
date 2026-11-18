#!/usr/bin/env bash
# One-time VM preparation (run as root on the Oracle VM, Ubuntu or Oracle Linux): user, directories, unit, env template, OS firewall for UDP.
set -euo pipefail
PORT="${PORT:-2456}"
here="$(cd "$(dirname "$0")" && pwd)"
# Ubuntu Minimal has almost nothing installed: the scripts need openssl (certificate), coreutils stdbuf (log buffering, already present) and curl.
if command -v apt-get >/dev/null 2>&1; then DEBIAN_FRONTEND=noninteractive apt-get install -y openssl curl ca-certificates >/dev/null; fi
id peepeechess >/dev/null 2>&1 || useradd --system --home /var/lib/peepeechess --shell /usr/sbin/nologin peepeechess
mkdir -p /opt/peepeechess/releases /etc/peepeechess /var/lib/peepeechess
chown peepeechess:peepeechess /var/lib/peepeechess
install -m 644 "$here/../systemd/peepeechess-server.service" /etc/systemd/system/peepeechess-server.service
[ -f /etc/peepeechess/server.env ] || install -m 600 "$here/../systemd/server.env.example" /etc/peepeechess/server.env
if command -v ufw >/dev/null 2>&1; then ufw allow "$PORT/udp" || true; fi
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PORT/udp" && firewall-cmd --reload || true
fi
# Oracle's Ubuntu images ship an iptables rule set that rejects everything but SSH: allow the game's UDP port there too and keep it across reboots.
if command -v iptables >/dev/null 2>&1 && iptables -S INPUT 2>/dev/null | grep -q -- "-j REJECT"; then
  iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT
  if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save || true
  else echo "NOTE: install iptables-persistent (apt-get install -y iptables-persistent) and run 'netfilter-persistent save' so the rule survives a reboot."; fi
fi
systemctl daemon-reload
echo "Next: sudo $here/make_cert.sh <public-ip>   (creates the certificate), edit /etc/peepeechess/server.env if needed, then install a release."
echo "Also open UDP $PORT in the OCI security list / network security group."
