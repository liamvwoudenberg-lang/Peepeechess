#!/usr/bin/env bash
# Package the account service (server/native: sign-up, login, friends, ratings, matchmaking tickets) for a VM.
#   tools/deploy/build_accounts.sh [out_dir]
# Output: <out_dir>/peepeechess-accounts-<sha>.tar.gz (+ .sha256): the TypeScript sources, only the four runtime dependencies (installed here, so the VM
# needs no npm), VERSION and run-accounts.sh. The VM runs it with Node 24 (remote/bootstrap_accounts.sh installs it). Build on Linux x86_64 for an x86_64 VM.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$(realpath -m "${1:-$ROOT/artifacts/accounts-release}")"
SHA="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/pkg"; mkdir -p "$PKG/server/native" "$PKG/contracts/application" "$OUT"
cp "$ROOT"/server/native/*.ts "$PKG/server/native/"
cp -r "$ROOT/contracts/application/v1" "$PKG/contracts/application/v1"
node - "$ROOT/package.json" "$PKG/package.json" <<'JS'
const fs = require('fs'); const root = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const dependencies = {}; for (const name of ['dotenv', 'express', 'pg', 'tsx']) dependencies[name] = root.dependencies[name] || root.devDependencies?.[name];
for (const [name, v] of Object.entries(dependencies)) if (!v) throw Error('missing dependency ' + name);
fs.writeFileSync(process.argv[3], JSON.stringify({ name: 'peepeechess-accounts', private: true, type: root.type || 'commonjs', dependencies }, null, 2) + '\n');
JS
(cd "$PKG" && npm install --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error)
cat > "$PKG/run-accounts.sh" <<'RUN'
#!/usr/bin/env bash
# Starts the account service. Settings come from the environment (systemd EnvironmentFile /etc/peepeechess/accounts.env); no secret is stored here.
# The game server's DTLS certificate is advertised to players so their game can trust it without a file.
here="$(cd "$(dirname "$0")" && pwd)"
NODE="${NODE_BIN:-/opt/peepeechess/node/bin/node}"
if [ -z "${NATIVE_GAME_CA_CERTIFICATE:-}" ] && [ -f /etc/peepeechess/server.crt ]; then export NATIVE_GAME_CA_CERTIFICATE="$(cat /etc/peepeechess/server.crt)"; fi
cd "$here"
exec "$NODE" --import tsx server/native/main.ts
RUN
chmod +x "$PKG/run-accounts.sh"
printf 'commit=%s\nbuilt=%s\n' "$SHA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PKG/VERSION"
TAR="$OUT/peepeechess-accounts-$SHA.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$PKG" -czf "$TAR" .
(cd "$OUT" && sha256sum "$(basename "$TAR")" > "$(basename "$TAR").sha256")
echo "built $TAR ($(du -h "$TAR" | cut -f1))"; cat "$TAR.sha256"
