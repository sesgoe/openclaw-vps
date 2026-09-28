#!/usr/bin/env bash
# Runs on the HEY gateway as root (scripts/login.sh does this): signs the service user
# in to HEY with the full hey CLI, then deletes that binary. Only the restricted
# hey-gordy is left behind, reading the credentials this writes.
set -euo pipefail
rm -f -- "$0" # a copy uploaded to /tmp; nothing to keep

src="${1:?usage: login-hey.sh <full hey binary> <sha256>}"
expected="${2:?usage: login-hey.sh <full hey binary> <sha256>}"
service_user=hey

actual="$(sha256sum -- "$src" | cut -d' ' -f1)"
if [[ "$actual" != "$expected" ]]; then
  printf 'error: checksum mismatch for %s\n' "$src" >&2
  rm -f -- "$src"
  exit 1
fi

workdir="$(mktemp -d /tmp/hey-login.XXXXXX)"
cleanup() { rm -rf -- "$workdir" "$src"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
chmod 0755 "$workdir"
install -m 0755 -o root -g root -- "$src" "$workdir/hey"

cat <<'EOF'

Signing in to HEY as the gateway's service user.

  1. Open the URL printed below in your workstation's browser and approve access.
  2. HEY then redirects to http://127.0.0.1:<port>/callback?... on *this* machine, so
     your browser shows a page that fails to load. Copy that whole URL.
  3. In a second terminal on your workstation, hand it over:

       make login-callback URL='<the URL you copied>'

EOF

sudo -H -u "$service_user" env HEY_NO_KEYRING=1 "$workdir/hey" auth login --no-browser

printf '\nChecking the restricted binary can use the sign-in...\n'
sudo -n -H -u "$service_user" /usr/local/libexec/hey-gordy account list
