#!/usr/bin/env bash
# Creates the server's DTLS certificate and key (self-signed, valid 825 days) for the address clients will use, and prints the SHA-256
# fingerprint so you can check that the certificate a client holds is the real one.
#   sudo make_cert.sh <public-ip-or-hostname>
# The private key stays on the VM (mode 600, owner peepeechess). Copy ONLY /etc/peepeechess/server.crt to your players (it is public).
set -euo pipefail
NAME="${1:?usage: make_cert.sh <public-ip-or-hostname>}"
DIR=/etc/peepeechess
command -v openssl >/dev/null || { echo "openssl is missing: apt-get install -y openssl" >&2; exit 2; }
if [ -f "$DIR/server.key" ] && [ -z "${FORCE:-}" ]; then echo "$DIR/server.key exists; set FORCE=1 to replace it (clients must then be given the new server.crt)" >&2; exit 3; fi
if [[ "$NAME" =~ ^[0-9.]+$ ]]; then SAN="IP:$NAME"; else SAN="DNS:$NAME"; fi
umask 077
openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=$NAME" -addext "subjectAltName=$SAN" -keyout "$DIR/server.key" -out "$DIR/server.crt"
chown peepeechess:peepeechess "$DIR/server.key" "$DIR/server.crt" 2>/dev/null || true
chmod 600 "$DIR/server.key"; chmod 644 "$DIR/server.crt"
echo "created $DIR/server.crt for $NAME"
openssl x509 -in "$DIR/server.crt" -noout -fingerprint -sha256 -enddate
