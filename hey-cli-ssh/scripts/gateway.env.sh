# Shared settings for the workstation-side scripts. Override any of them in the environment.
# shellcheck shell=bash

HEY_GATEWAY_ADMIN="${HEY_GATEWAY_ADMIN:-hey-admin@hey-gateway}"
HEY_GATEWAY_SSH_KEY="${HEY_GATEWAY_SSH_KEY:-$HOME/.ssh/openclaw_admin}"
HEY_CLI_BIN_DIR="${HEY_CLI_BIN_DIR:-$HOME/personal/forks/hey-cli/bin}"
# The gateway's host key is trusted on first use and kept apart from ~/.ssh/known_hosts,
# so a rebuilt gateway (new key) only needs this file removed; bring-up.sh does that.
HEY_GATEWAY_KNOWN_HOSTS="${HEY_GATEWAY_KNOWN_HOSTS:-$HOME/.ssh/known_hosts.hey-gateway}"

require_built() {
  if [[ ! -f "$1" || ! -f "$1.sha256" ]]; then
    printf 'error: %s (and its .sha256) not found; run scripts/build-hey-gordy.sh in the hey-cli fork\n' "$1" >&2
    exit 1
  fi
}

gateway_ssh_opts=(
  -i "$HEY_GATEWAY_SSH_KEY" -o IdentitiesOnly=yes
  -o UserKnownHostsFile="$HEY_GATEWAY_KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new
)

gateway_scp() {
  scp "${gateway_ssh_opts[@]}" "$@"
}

gateway_ssh() {
  ssh -t "${gateway_ssh_opts[@]}" "$HEY_GATEWAY_ADMIN" "$@"
}

gateway_ssh_batch() {
  ssh -T "${gateway_ssh_opts[@]}" "$HEY_GATEWAY_ADMIN" "$@"
}
