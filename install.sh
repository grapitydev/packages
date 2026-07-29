#!/bin/sh
# grapity installer — https://packages.grapity.dev/install.sh
#
#   curl -fsSL https://packages.grapity.dev/install.sh | sh
#
# macOS and Linux only. Detects your package manager and installs through it
# (Homebrew, apt, dnf, pacman) so updates arrive via normal system upgrades.
# Without a known package manager, falls back to a checksum-verified binary
# from GitHub Releases. Windows: use npm (npm install -g @grapity/grapity)
# or run this script inside WSL.
#
# Environment overrides:
#   GRAPITY_VERSION=v0.10.0   install a specific version (default: latest)
#   GRAPITY_BIN_DIR=~/.local/bin
#                             binary install location (default: /usr/local/bin
#                             when writable/sudo available, else ~/.local/bin)
#   GRAPITY_FORCE_BINARY=1    skip package managers, use the binary fallback

set -eu
# shellcheck disable=SC3040
(set -o pipefail) 2>/dev/null && set -o pipefail

REPO_URL="https://packages.grapity.dev"
GH_REPO="grapitydev/grapity"
GRAPITY_VERSION="${GRAPITY_VERSION:-latest}"
GRAPITY_BIN_DIR="${GRAPITY_BIN_DIR:-}"
GRAPITY_FORCE_BINARY="${GRAPITY_FORCE_BINARY:-}"

info() { printf '%s\n' "==> $*"; }
warn() { printf '%s\n' "warning: $*" >&2; }
die() { printf '%s\n' "error: $*" >&2; exit 1; }

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    die "Windows is not supported by this installer. Use npm (npm install -g @grapity/grapity) or run inside WSL."
    ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required but not installed."

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

require_root() {
  if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
    die "root privileges (sudo) are required for package-manager installs. Re-run with sudo, or use GRAPITY_FORCE_BINARY=1 for a user-local install."
  fi
}

install_brew() {
  info "Detected macOS with Homebrew — installing grapitydev/tap/grapity"
  info "+ brew install grapitydev/tap/grapity"
  brew install grapitydev/tap/grapity
}

install_apt() {
  require_root
  info "Detected apt (Debian/Ubuntu) — setting up the grapity repository"
  info "+ $SUDO apt-get update"
  $SUDO apt-get update
  if ! command -v gpg >/dev/null 2>&1; then
    info "+ $SUDO apt-get install -y gpg ca-certificates"
    $SUDO apt-get install -y gpg ca-certificates
  fi
  info "+ curl $REPO_URL/gpg.key | $SUDO gpg --dearmor -o /usr/share/keyrings/grapity.gpg"
  curl -fsSL "$REPO_URL/gpg.key" | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/grapity.gpg
  info "+ $SUDO tee /etc/apt/sources.list.d/grapity.list"
  echo "deb [signed-by=/usr/share/keyrings/grapity.gpg] $REPO_URL/apt stable main" | $SUDO tee /etc/apt/sources.list.d/grapity.list
  info "+ $SUDO apt-get install -y grapity"
  $SUDO apt-get update
  $SUDO apt-get install -y grapity
}

install_dnf() {
  require_root
  info "Detected dnf (Fedora/RHEL) — setting up the grapity repository"
  info "+ $SUDO dnf config-manager addrepo --from-repofile=$REPO_URL/dnf/grapity.repo"
  $SUDO dnf config-manager addrepo --from-repofile="$REPO_URL/dnf/grapity.repo"
  info "+ $SUDO dnf install -y grapity"
  $SUDO dnf install -y grapity
}

install_pacman() {
  require_root
  info "Detected pacman (Arch) — setting up the grapity repository"
  if ! grep -q '^\[grapity\]' /etc/pacman.conf 2>/dev/null; then
    info "+ $SUDO tee -a /etc/pacman.conf ([grapity] repo block)"
    printf "[grapity]\nSigLevel = Required DatabaseOptional\nServer = %s/pacman/\$arch\n" "$REPO_URL" | $SUDO tee -a /etc/pacman.conf
  fi
  info "+ curl $REPO_URL/gpg.key | $SUDO pacman-key --add -"
  curl -fsSL "$REPO_URL/gpg.key" | $SUDO pacman-key --add -
  if ! $SUDO pacman-key --lsign-key contact@grapity.dev 2>/dev/null; then
    warn "pacman keyring not initialized — running pacman-key --init"
    $SUDO pacman-key --init
    info "+ $SUDO pacman-key --lsign-key contact@grapity.dev"
    $SUDO pacman-key --lsign-key contact@grapity.dev
  fi
  info "+ $SUDO pacman -Sy --noconfirm grapity"
  $SUDO pacman -Sy --noconfirm grapity
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

install_binary() {
  case "$ARCH" in
    x86_64|amd64) target_arch="x64" ;;
    arm64|aarch64) target_arch="arm64" ;;
    *) die "unsupported architecture: $ARCH" ;;
  esac
  case "$OS" in
    Darwin) target_os="darwin" ;;
    Linux) target_os="linux" ;;
    *) die "unsupported OS: $OS" ;;
  esac

  if [ "$target_os" = "linux" ] && { ldd --version 2>&1 | grep -qi musl || ls /lib/ld-musl-* >/dev/null 2>&1; }; then
    die "musl-based system detected (e.g. Alpine): grapity binaries are glibc builds. Use npm (npm install -g @grapity/grapity) instead."
  fi

  asset="grapity-${target_os}-${target_arch}"
  version="$GRAPITY_VERSION"
  if [ "$version" = "latest" ]; then
    version="$(curl -fsSIL "https://github.com/${GH_REPO}/releases/latest" -o /dev/null -w '%{url_effective}' | sed 's/.*\///')"
  fi
  [ -n "$version" ] || die "could not resolve the latest release version."
  info "Installing $asset $version (checksum-verified binary)"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/${GH_REPO}/releases/download/${version}"
  info "+ curl $base/$asset"
  curl -fsSL "$base/$asset" -o "$tmp/grapity"
  info "+ curl $base/checksums.txt"
  curl -fsSL "$base/checksums.txt" -o "$tmp/checksums.txt" ||
    die "checksums.txt not found for $version; cannot verify the download. See https://grapity.dev/docs/getting-started/installation/ for manual options."

  expected="$(awk -v f="$asset" '$2 == f {print $1}' "$tmp/checksums.txt")"
  [ -n "$expected" ] || die "no checksum entry for $asset in checksums.txt."
  actual="$(sha256_of "$tmp/grapity")"
  [ "$actual" = "$expected" ] || die "checksum mismatch for $asset (expected $expected, got $actual). Aborting."
  info "Checksum verified (sha256)"

  bin_dir="$GRAPITY_BIN_DIR"
  if [ -z "$bin_dir" ]; then
    if [ -w /usr/local/bin ] || [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
      bin_dir="/usr/local/bin"
    else
      bin_dir="$HOME/.local/bin"
    fi
  fi
  if [ ! -d "$bin_dir" ]; then
    info "+ mkdir -p $bin_dir"
    if [ "$bin_dir" = "/usr/local/bin" ]; then $SUDO mkdir -p "$bin_dir"; else mkdir -p "$bin_dir"; fi
  fi
  info "+ install -m 0755 grapity $bin_dir/grapity"
  if [ -w "$bin_dir" ]; then
    install -m 0755 "$tmp/grapity" "$bin_dir/grapity"
  else
    $SUDO install -m 0755 "$tmp/grapity" "$bin_dir/grapity"
  fi
  rm -rf "$tmp"
  trap - EXIT

  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) warn "$bin_dir is not on your PATH. Add it, e.g.: export PATH=\"$bin_dir:\$PATH\"" ;;
  esac
}

main() {
  info "grapity installer (macOS/Linux) — detected $OS $ARCH"
  if [ "$OS" = "Darwin" ]; then
    if [ -z "$GRAPITY_FORCE_BINARY" ] && command -v brew >/dev/null 2>&1; then
      install_brew
    else
      install_binary
    fi
  elif [ "$OS" = "Linux" ]; then
    if [ -n "$GRAPITY_FORCE_BINARY" ]; then
      install_binary
    elif command -v apt-get >/dev/null 2>&1; then
      install_apt
    elif command -v dnf >/dev/null 2>&1; then
      install_dnf
    elif command -v pacman >/dev/null 2>&1; then
      install_pacman
    else
      install_binary
    fi
  else
    die "unsupported OS: $OS (Windows: use npm or WSL)"
  fi

  command -v grapity >/dev/null 2>&1 || die "installation finished but grapity is not on your PATH. See https://grapity.dev/docs/getting-started/installation/"
  info "grapity $(grapity --version) installed. Run 'grapity init --local' to get started."
}

main
