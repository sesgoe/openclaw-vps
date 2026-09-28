#!/usr/bin/env bash
# Sign the HEY gateway in to HEY, with the full hey CLI copied over for the purpose and
# deleted afterwards. `login.sh callback <url>` hands the browser's redirect to it.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/gateway.env.sh
source "${here}/gateway.env.sh"

if [[ "${1:-}" == "callback" ]]; then
  url="${2:?usage: login.sh callback <url>}"
  if [[ ! "$url" =~ ^http://127\.0\.0\.1:[0-9]+/callback\? ]]; then
    printf 'error: expected the http://127.0.0.1:<port>/callback?... URL your browser failed to load\n' >&2
    exit 1
  fi
  # The URL travels on stdin so no shell on either side ever parses it.
  printf '%s\n' "$url" | gateway_ssh_batch 'read -r url; curl -fsS --max-time 10 -o /dev/null -- "$url" && echo "Delivered the sign-in to the gateway."'
  exit 0
fi

binary="${HEY_CLI_BIN_DIR}/hey-linux-amd64"
require_built "$binary"
sha="$(cut -d' ' -f1 < "${binary}.sha256")"

gateway_scp "$binary" "${here}/remote/login-hey.sh" "${HEY_GATEWAY_ADMIN}:/tmp/"
gateway_ssh "sudo bash /tmp/login-hey.sh /tmp/hey-linux-amd64 ${sha}"
