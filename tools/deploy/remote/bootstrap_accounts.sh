#!/usr/bin/env bash
# One-time VM preparation for the account service (run as root, after bootstrap_vm.sh): swap, Node 24, Caddy, directories, units, a freshly
# generated shared secret, and the web ports. It does NOT start anything and changes nothing about the running game server.
#   sudo bootstrap_accounts.sh <public-ip> [domain]
# domain defaults to <ip with dashes>.sslip.io (a public wildcard DNS name that points at the IP: no domain purchase needed).
set -euo pipefail
IP="${1:?usage: bootstrap_accounts.sh <public-ip> [domain]}"
DOMAIN="${2:-${IP//./-}.sslip.io}"
NODE_VERSION="${NODE_VERSION:-24.22.1}"
CADDY_VERSION="${CADDY_VERSION:-2.10.2}"
here="$(cd "$(dirname "$0")" && pwd)"
[ "$(uname -m)" = x86_64 ] || { echo "this script installs x86_64 binaries (VM.Standard.E2.1.Micro); this machine is $(uname -m)" >&2; exit 2; }
command -v curl >/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates xz-utils >/dev/null; }
command -v xz >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y xz-utils >/dev/null
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. Swap: a 1 GB VM running three services needs a safety net.
if [ "$(swapon --show --noheadings | wc -l)" -eq 0 ]; then
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "created a 1 GB swap file"
fi

# 2. Node (official tarball, SHA-256 checked against nodejs.org's list).
if [ ! -x /opt/peepeechess/node/bin/node ] || ! /opt/peepeechess/node/bin/node -v | grep -q "^v$NODE_VERSION$"; then
  curl -fL --retry 3 "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" -o "$TMP/node.tar.xz"
  curl -fL --retry 3 "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" -o "$TMP/SHASUMS256.txt"
  (cd "$TMP" && grep " node-v$NODE_VERSION-linux-x64.tar.xz\$" SHASUMS256.txt | awk '{print $1 "  node.tar.xz"}' | sha256sum -c -)
  mkdir -p /opt/peepeechess && rm -rf "/opt/peepeechess/node-$NODE_VERSION" && mkdir "/opt/peepeechess/node-$NODE_VERSION"
  tar -xJf "$TMP/node.tar.xz" -C "/opt/peepeechess/node-$NODE_VERSION" --strip-components=1
  ln -sfn "/opt/peepeechess/node-$NODE_VERSION" /opt/peepeechess/node
fi
echo "node $(/opt/peepeechess/node/bin/node -v)"

# 3. Caddy (official release, checksum from the same release).
if ! /usr/local/bin/caddy version 2>/dev/null | grep -q "v$CADDY_VERSION"; then
  base="https://github.com/caddyserver/caddy/releases/download/v$CADDY_VERSION"
  curl -fL --retry 3 "$base/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" -o "$TMP/caddy.tar.gz"
  curl -fL --retry 3 "$base/caddy_${CADDY_VERSION}_checksums.txt" -o "$TMP/caddy.sums"
  (cd "$TMP" && grep " caddy_${CADDY_VERSION}_linux_amd64.tar.gz\$" caddy.sums | awk '{print $1 "  caddy.tar.gz"}' | sha512sum -c -)
  tar -xzf "$TMP/caddy.tar.gz" -C "$TMP" caddy && install -m 755 "$TMP/caddy" /usr/local/bin/caddy
fi
id caddy >/dev/null 2>&1 || useradd --system --home /var/lib/caddy --shell /usr/sbin/nologin caddy
mkdir -p /var/lib/caddy /etc/caddy && chown -R caddy:caddy /var/lib/caddy
sed "s/@DOMAIN@/$DOMAIN/" "$here/../systemd/Caddyfile.template" > /etc/caddy/Caddyfile
install -m 644 "$here/../systemd/caddy.service" /etc/systemd/system/caddy.service

# 4. Account service: user, directories, unit, environment with a generated secret (never printed).
id peepeechess >/dev/null 2>&1 || useradd --system --home /var/lib/peepeechess --shell /usr/sbin/nologin peepeechess
mkdir -p /opt/peepeechess-accounts/releases /etc/peepeechess /var/lib/peepeechess
chown peepeechess:peepeechess /var/lib/peepeechess
install -m 644 "$here/../systemd/peepeechess-accounts.service" /etc/systemd/system/peepeechess-accounts.service
if [ ! -f /etc/peepeechess/accounts.env ]; then
  umask 077
  sed -e "s/^NATIVE_SERVER_SECRET=.*/NATIVE_SERVER_SECRET=$(openssl rand -hex 32)/" -e "s/203\.0\.113\.10/$IP/g" "$here/../systemd/accounts.env.example" > /etc/peepeechess/accounts.env
  echo "created /etc/peepeechess/accounts.env (new secret, mode 600)"
fi
echo "$DOMAIN" > /etc/peepeechess/accounts.domain

# 5. Web ports for HTTPS (Let's Encrypt needs 80 as well as 443).
if command -v ufw >/dev/null 2>&1; then ufw allow 80/tcp || true; ufw allow 443/tcp || true; fi
if command -v iptables >/dev/null 2>&1 && iptables -S INPUT 2>/dev/null | grep -q -- "-j REJECT"; then
  for p in 80 443; do iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport $p -j ACCEPT; done
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save || true
fi
systemctl daemon-reload
echo "Done. Account URL will be https://$DOMAIN"
echo "Also open TCP 80 and TCP 443 in the Oracle Security List (Source 0.0.0.0/0). Nothing is running yet: install a release, then run enable_accounts.sh."
