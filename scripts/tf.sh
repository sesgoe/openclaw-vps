#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
infra_dir="${repo_dir}/infra"
action="${1:-}"

usage() {
  printf 'usage: %s {init|fmt|validate|plan|apply|output}\n' "$0" >&2
  exit 2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_digitalocean_token() {
  if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
    printf 'error: DIGITALOCEAN_TOKEN is not set\n' >&2
    exit 1
  fi
}

require_plan_environment() {
  local missing=0

  if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
    printf 'error: DIGITALOCEAN_TOKEN is not set\n' >&2
    missing=1
  fi
  if [[ -z "${TF_VAR_tailscale_auth_key:-}" ]]; then
    printf 'error: TF_VAR_tailscale_auth_key is not set\n' >&2
    missing=1
  fi
  if [[ -z "${TF_VAR_ssh_public_key:-}" ]]; then
    printf 'error: TF_VAR_ssh_public_key is not set\n' >&2
    missing=1
  fi

  if (( missing != 0 )); then
    printf 'See README.md for safe environment-variable setup.\n' >&2
    exit 1
  fi
}

require_command terraform

case "$action" in
  init)
    terraform -chdir="$infra_dir" init
    ;;
  fmt)
    terraform -chdir="$infra_dir" fmt -check -diff
    ;;
  validate)
    terraform -chdir="$infra_dir" validate
    ;;
  plan)
    require_plan_environment
    terraform -chdir="$infra_dir" plan -out=openclaw.tfplan
    ;;
  apply)
    require_digitalocean_token
    if [[ ! -f "${infra_dir}/openclaw.tfplan" ]]; then
      printf 'error: no saved plan; run make plan first\n' >&2
      exit 1
    fi
    terraform -chdir="$infra_dir" apply openclaw.tfplan
    rm -f -- "${infra_dir}/openclaw.tfplan"
    ;;
  output)
    terraform -chdir="$infra_dir" output
    ;;
  *)
    usage
    ;;
esac
