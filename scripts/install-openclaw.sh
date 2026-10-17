#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly NODE_MAJOR=26
readonly DEFAULT_OPENCLAW_VERSION="latest"
readonly NPM_PREFIX="${HOME}/.local"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: install-openclaw.sh [OPENCLAW_VERSION]

Prepare the OpenClaw Ubuntu host and install OpenClaw for the current user.
OPENCLAW_VERSION may be an npm version or dist-tag and defaults to "latest".

Examples:
  ./install-openclaw.sh
  ./install-openclaw.sh 2026.7.1-2
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

(( $# <= 1 )) || die "expected at most one OpenClaw version"

readonly OPENCLAW_VERSION="${1:-${DEFAULT_OPENCLAW_VERSION}}"
[[ "${OPENCLAW_VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || \
  die "invalid OpenClaw version: ${OPENCLAW_VERSION}"

(( EUID != 0 )) || die "run this script as the OpenClaw administrator, not as root; it invokes sudo when needed"
command -v sudo >/dev/null 2>&1 || die "sudo is required"
command -v apt-get >/dev/null 2>&1 || die "apt-get is required"
[[ -r /etc/os-release ]] || die "cannot identify the operating system"

# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" =~ ^(24.04|26.04)$ ]] || \
  die "this script supports Ubuntu 24.04 and 26.04; found ${PRETTY_NAME:-unknown OS}"

readonly DEB_ARCH="$(dpkg --print-architecture)"
[[ "${DEB_ARCH}" == "amd64" ]] || \
  die "Google Chrome's Linux package requires amd64; found ${DEB_ARCH}"

readonly TEMP_DIR="$(mktemp -d)"
chmod 0755 "${TEMP_DIR}"
cleanup() {
  rm -rf -- "${TEMP_DIR}"
}
trap cleanup EXIT

log "Checking sudo access"
if ! sudo -n true 2>/dev/null; then
  sudo -v
fi

log "Installing host tools and native build/media dependencies"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  dbus-user-session \
  ffmpeg \
  fonts-liberation \
  fonts-noto-color-emoji \
  git \
  gnupg \
  jq \
  python3 \
  python3-venv \
  ripgrep \
  sox \
  unzip \
  xdg-utils

log "Enabling the OpenClaw administrator's user services at boot"
sudo loginctl enable-linger "$(id -un)"

log "Configuring the NodeSource Node.js ${NODE_MAJOR} repository"
curl --proto '=https' --tlsv1.2 -fsSLo "${TEMP_DIR}/nodesource.asc" \
  https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
gpg --batch --yes --dearmor \
  --output "${TEMP_DIR}/nodesource.gpg" \
  "${TEMP_DIR}/nodesource.asc"
sudo install -o root -g root -m 0644 \
  "${TEMP_DIR}/nodesource.gpg" \
  /usr/share/keyrings/nodesource.gpg

cat >"${TEMP_DIR}/nodesource.sources" <<EOF
Types: deb
URIs: https://deb.nodesource.com/node_${NODE_MAJOR}.x
Suites: nodistro
Components: main
Architectures: ${DEB_ARCH}
Signed-By: /usr/share/keyrings/nodesource.gpg
EOF
sudo install -o root -g root -m 0644 \
  "${TEMP_DIR}/nodesource.sources" \
  /etc/apt/sources.list.d/nodesource.sources

CHROME_INSTALL_TARGET="google-chrome-stable"
if ! dpkg-query --show --showformat='${Status}\n' google-chrome-stable 2>/dev/null | \
  grep -Fqx 'install ok installed'; then
  log "Downloading the current stable Google Chrome package"
  curl --proto '=https' --tlsv1.2 -fsSLo "${TEMP_DIR}/google-chrome.deb" \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  chmod 0644 "${TEMP_DIR}/google-chrome.deb"
  CHROME_INSTALL_TARGET="${TEMP_DIR}/google-chrome.deb"
else
  log "Google Chrome is already installed; using its configured APT repository"
fi
readonly CHROME_INSTALL_TARGET

log "Installing Node.js ${NODE_MAJOR} and Google Chrome"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nodejs \
  "${CHROME_INSTALL_TARGET}"

readonly INSTALLED_NODE_MAJOR="$(/usr/bin/node --version | sed -E 's/^v([0-9]+).*/\1/')"
[[ "${INSTALLED_NODE_MAJOR}" == "${NODE_MAJOR}" ]] || \
  die "expected Node.js ${NODE_MAJOR}, found $(/usr/bin/node --version)"

log "Configuring user-local npm packages under ${NPM_PREFIX}"
install -d -m 0755 "${NPM_PREFIX}/bin"
npm config set prefix "${NPM_PREFIX}" --location=user

readonly PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
touch "${HOME}/.profile"
if ! grep -Fqx "${PATH_LINE}" "${HOME}/.profile"; then
  printf '\n%s\n' "${PATH_LINE}" >>"${HOME}/.profile"
fi
export PATH="${NPM_PREFIX}/bin:${PATH}"

log "Resolving openclaw@${OPENCLAW_VERSION}"
readonly RESOLVED_OPENCLAW_VERSION="$(npm view "openclaw@${OPENCLAW_VERSION}" version)"
[[ "${RESOLVED_OPENCLAW_VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || \
  die "npm returned an invalid OpenClaw version: ${RESOLVED_OPENCLAW_VERSION}"

INSTALLED_OPENCLAW_VERSION=""
readonly OPENCLAW_PACKAGE_JSON="$(npm root --global)/openclaw/package.json"
if [[ -r "${OPENCLAW_PACKAGE_JSON}" ]]; then
  INSTALLED_OPENCLAW_VERSION="$(node -p 'require(process.argv[1]).version' "${OPENCLAW_PACKAGE_JSON}")"
fi
readonly INSTALLED_OPENCLAW_VERSION

if [[ "${INSTALLED_OPENCLAW_VERSION}" == "${RESOLVED_OPENCLAW_VERSION}" ]]; then
  log "OpenClaw ${RESOLVED_OPENCLAW_VERSION} is already installed"
else
  log "Installing OpenClaw ${RESOLVED_OPENCLAW_VERSION} as the current user"
  npm install --global --no-audit --no-fund \
    --allow-scripts=openclaw \
    "openclaw@${RESOLVED_OPENCLAW_VERSION}"
fi
hash -r

command -v openclaw >/dev/null 2>&1 || die "OpenClaw installed but is not on PATH"
command -v google-chrome-stable >/dev/null 2>&1 || die "Google Chrome is not on PATH"

log "Installation complete"
printf 'Node.js:  %s\n' "$(node --version)"
printf 'npm:      %s\n' "$(npm --version)"
printf 'Chrome:   %s\n' "$(google-chrome-stable --version)"
printf 'OpenClaw: %s\n' "$(openclaw --version)"
printf 'Linger:   %s\n' "$(loginctl show-user "$(id -un)" --property=Linger --value)"
if [[ -f /var/run/reboot-required ]]; then
  printf 'Reboot:   required to activate installed system updates\n'
else
  printf 'Reboot:   not required\n'
fi
printf '\nStart a new SSH session (or run: source ~/.profile), then run:\n'
printf '  openclaw onboard --install-daemon\n'
