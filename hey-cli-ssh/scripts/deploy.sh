#!/usr/bin/env bash
# Copy the restricted hey-gordy binary to the HEY gateway and install it.
#
# Build it first in the hey-cli fork: scripts/build-hey-gordy.sh
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/gateway.env.sh
source "${here}/gateway.env.sh"

binary="${HEY_CLI_BIN_DIR}/hey-gordy-linux-amd64"
require_built "$binary"
sha="$(cut -d' ' -f1 < "${binary}.sha256")"

gateway_scp "$binary" "${here}/remote/install-hey-gordy.sh" "${HEY_GATEWAY_ADMIN}:/tmp/"
gateway_ssh "sudo bash /tmp/install-hey-gordy.sh /tmp/hey-gordy-linux-amd64 ${sha}"
