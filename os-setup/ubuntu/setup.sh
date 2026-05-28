#!/usr/bin/env bash
#
# Fresh Ubuntu bootstrap: zsh + Oh My Zsh + plugins + dotfiles.
# Safe to re-run.

set -euo pipefail

# ─── pretty output ────────────────────────────────────────────────────────────
BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
CYAN=$'\e[1;36m'; GREEN=$'\e[1;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[1;31m'; MAGENTA=$'\e[1;35m'

step()  { printf '\n%s==>%s %s[%d/%d]%s %s%s%s\n' "$CYAN" "$RESET" "$DIM" "$1" "$TOTAL_STEPS" "$RESET" "$BOLD" "$2" "$RESET"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
info()  { printf '  %s·%s %s\n' "$DIM" "$RESET" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
die()   { printf '\n%s✗%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

banner() {
  printf '\n%s' "$MAGENTA"
  cat <<'EOF'
  ╭─────────────────────────────────────────────╮
  │      gleitao · ubuntu dotfiles bootstrap    │
  ╰─────────────────────────────────────────────╯
EOF
  printf '%s\n' "$RESET"
}

TOTAL_STEPS=7
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── argument parsing ────────────────────────────────────────────────────────
FILESYSTEMS=""
NO_DISK_INFO=false

usage() {
  cat <<EOF
${BOLD}usage:${RESET} $(basename "$0") [options]

  -f, --filesystems "<a,b,c>"   Replace the default WSL/LVM device paths in
                                ~/.zshrc with this comma-separated list of
                                grep patterns for 'df -h' output.
                                Example: --filesystems "/dev/sda1,/dev/sda2"

      --no-disk-info            Strip the 'df -h' disk-info lines from the
                                .zshrc personalization block entirely.

  -h, --help                    Show this help and exit.

If no flag is given, the default WSL/LVM paths
(/dev/mapper/volgroup0-lv_root and /dev/mapper/volgroup0-lv_home) are kept.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--filesystems) FILESYSTEMS="${2:-}"; shift 2 ;;
    --no-disk-info)   NO_DISK_INFO=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                printf '%sunknown option:%s %s\n' "$RED" "$RESET" "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$NO_DISK_INFO" == "true" && -n "$FILESYSTEMS" ]]; then
  printf '%s✗%s --filesystems and --no-disk-info are mutually exclusive\n' "$RED" "$RESET" >&2
  exit 2
fi

# ─── sanity checks ────────────────────────────────────────────────────────────
banner

[[ $EUID -ne 0 ]] || die "Don't run this as root. Run as your normal user; sudo will be invoked when needed."
command -v sudo >/dev/null || die "sudo is required but not installed."
[[ -f /etc/os-release ]] && . /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]] || warn "This script targets Ubuntu/Debian; detected '${ID:-unknown}'."

info "Caching sudo credentials (you may be prompted once)…"
sudo -v
# keep sudo alive for the duration of the script
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ─── 1. update apt ────────────────────────────────────────────────────────────
step 1 "Updating package index and upgrading system"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq
ok "System packages up to date"

# ─── 2. install base packages + handy CLI extras ─────────────────────────────
step 2 "Installing base packages and handy CLI extras"

# Filter requested list against apt's catalog: older Ubuntu releases may not
# carry every package (e.g. btop is 22.04+). We install whatever is available
# and warn about the rest rather than failing the whole step.
PKGS_REQUESTED=(
  # tools this script itself needs
  zsh git curl wget ca-certificates
  # handy CLI extras you'll inevitably want on a fresh box
  tree htop btop neovim tmux unzip zip
  ripgrep fd-find bat jq
  openssh-client less man-db
  build-essential python3-pip
)
PKGS=()
SKIPPED=()
for p in "${PKGS_REQUESTED[@]}"; do
  if apt-cache show "$p" >/dev/null 2>&1; then
    PKGS+=("$p")
  else
    SKIPPED+=("$p")
  fi
done
(( ${#SKIPPED[@]} > 0 )) && warn "Not in apt on this release, skipping: ${SKIPPED[*]}"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${PKGS[@]}"
ok "Installed: ${PKGS[*]}"

# ─── 3. install fastfetch + gh (with repo fallbacks for older Ubuntu) ────────
step 3 "Installing fastfetch and gh"

# fastfetch — fall back to its PPA on older Ubuntu.
if command -v fastfetch >/dev/null; then
  ok "fastfetch already installed"
elif apt-cache show fastfetch >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fastfetch
  ok "fastfetch installed from apt"
else
  info "fastfetch not in apt repos; adding PPA ppa:zhangsongcui3371/fastfetch"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common
  sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fastfetch
  ok "fastfetch installed via PPA"
fi

# gh — fall back to the official GitHub CLI apt repo on older Ubuntu.
if command -v gh >/dev/null; then
  ok "gh already installed"
elif apt-cache show gh >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh
  ok "gh installed from apt"
else
  info "gh not in apt repos; adding the official GitHub CLI apt source"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh
  ok "gh installed via official GitHub CLI apt repo"
fi

# ─── 4. install Oh My Zsh (unattended, idempotent) ───────────────────────────
step 4 "Installing Oh My Zsh"
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
if [[ -d "$ZSH" ]]; then
  ok "Oh My Zsh already present at $ZSH"
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  ok "Oh My Zsh installed"
fi

# ─── 5. install zsh plugins (idempotent) ─────────────────────────────────────
step 5 "Installing zsh plugins"
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"

clone_plugin() {
  local name=$1 url=$2 dest="$ZSH_CUSTOM/plugins/$1"
  if [[ -d "$dest/.git" ]]; then
    info "$name already cloned, pulling latest"
    git -C "$dest" pull --quiet --ff-only || warn "Could not update $name"
  else
    git clone --quiet --depth=1 "$url" "$dest"
    ok "$name cloned"
  fi
}

clone_plugin zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions
clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting

# ─── 6. install .zshrc (with backup) ─────────────────────────────────────────
step 6 "Installing .zshrc"
SRC_ZSHRC="$SCRIPT_DIR/.zshrc"
DST_ZSHRC="$HOME/.zshrc"

[[ -f "$SRC_ZSHRC" ]] || die "Could not find $SRC_ZSHRC next to this script."

if [[ -f "$DST_ZSHRC" ]] && ! cmp -s "$SRC_ZSHRC" "$DST_ZSHRC"; then
  BACKUP="$DST_ZSHRC.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$DST_ZSHRC" "$BACKUP"
  info "Backed up existing .zshrc → $BACKUP"
fi
cp "$SRC_ZSHRC" "$DST_ZSHRC"
ok ".zshrc installed at $DST_ZSHRC"

# personalize the disk-info block based on flags
if [[ "$NO_DISK_INFO" == "true" ]]; then
  sed -i "/^df -h | GREP_COLORS='mt=1;36' grep/d" "$DST_ZSHRC"
  info "Stripped all 'df -h' disk-info lines from .zshrc"
elif [[ -n "$FILESYSTEMS" ]]; then
  replacement=""
  IFS=',' read -ra _FS_ARR <<< "$FILESYSTEMS"
  for fs in "${_FS_ARR[@]}"; do
    fs="${fs# }"; fs="${fs% }"  # trim surrounding spaces
    [[ -z "$fs" ]] && continue
    replacement+="df -h | GREP_COLORS='mt=1;36' grep \"$fs\""$'\n'
  done
  awk -v new="$replacement" '
    /grep "Filesystem[[:space:]]/    { print; printf "%s", new; next }
    /\/dev\/mapper\/volgroup0-lv_/   { next }
    { print }
  ' "$DST_ZSHRC" > "$DST_ZSHRC.tmp" && mv "$DST_ZSHRC.tmp" "$DST_ZSHRC"
  info "Replaced default disk paths with: ${_FS_ARR[*]}"
else
  info "Kept default WSL/LVM paths (use --filesystems to override)"
fi

# ─── 7. set zsh as default shell ─────────────────────────────────────────────
step 7 "Setting zsh as the default shell"
ZSH_BIN="$(command -v zsh)"

# make sure zsh is listed in /etc/shells (chsh refuses otherwise)
if ! grep -qxF "$ZSH_BIN" /etc/shells; then
  echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  info "Added $ZSH_BIN to /etc/shells"
fi

if [[ "${SHELL:-}" == "$ZSH_BIN" ]] && getent passwd "$USER" | cut -d: -f7 | grep -qxF "$ZSH_BIN"; then
  ok "zsh is already the default shell"
else
  sudo chsh -s "$ZSH_BIN" "$USER"
  ok "Default shell set to $ZSH_BIN (takes effect on next login)"
fi

# ─── done ────────────────────────────────────────────────────────────────────
printf '\n%s╭─────────────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
printf '%s│              all done — enjoy!              │%s\n' "$GREEN" "$RESET"
printf '%s╰─────────────────────────────────────────────╯%s\n\n' "$GREEN" "$RESET"

info "Dropping you into zsh now…"
exec "$ZSH_BIN" -l
