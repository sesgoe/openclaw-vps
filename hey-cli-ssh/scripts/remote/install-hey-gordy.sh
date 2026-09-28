#!/usr/bin/env bash
# Runs on the HEY gateway as root (scripts/deploy.sh does this): installs the restricted
# hey-gordy binary that the agent's forced command runs.
set -euo pipefail
rm -f -- "$0" # a copy uploaded to /tmp; nothing to keep

src="${1:?usage: install-hey-gordy.sh <binary> <sha256>}"
expected="${2:?usage: install-hey-gordy.sh <binary> <sha256>}"
target=/usr/local/libexec/hey-gordy
service_user=hey

if [[ ! -f /var/lib/hey-gateway-bootstrap-complete ]]; then
  printf 'error: bootstrap has not finished; check: sudo cloud-init status --wait --long\n' >&2
  exit 1
fi

actual="$(sha256sum -- "$src" | cut -d' ' -f1)"
if [[ "$actual" != "$expected" ]]; then
  printf 'error: checksum mismatch for %s\n  expected %s\n  got      %s\n' "$src" "$expected" "$actual" >&2
  exit 1
fi

install -d -m 0755 -o root -g root "$(dirname "$target")"
install -m 0755 -o root -g root -- "$src" "$target"
rm -f -- "$src"

printf 'Installed %s: %s\n' "$target" "$("$target" --version)"

if sudo -n -H -u "$service_user" "$target" --json account list >/dev/null 2>&1; then
  printf 'HEY sign-in: present\n'
else
  printf 'HEY sign-in: missing; run make login from your workstation\n'
fi
