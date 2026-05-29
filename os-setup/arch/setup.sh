#!/usr/bin/env bash
#
# Fresh Arch Linux bootstrap: Hyprland + Catppuccin + zsh + dotfiles.
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
  │   gleitao · arch hyprland dotfiles bootstrap │
  ╰─────────────────────────────────────────────╯
EOF
  printf '%s\n' "$RESET"
}

TOTAL_STEPS=8
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── argument parsing ────────────────────────────────────────────────────────
FILESYSTEMS=""
NO_DISK_INFO=false
NO_REBOOT=false
SKIP_THEME_GUI=false
NO_SERVICES=false

usage() {
  cat <<EOF
${BOLD}usage:${RESET} $(basename "$0") [options]

  -f, --filesystems "<a,b,c>"   Replace the default WSL/LVM device paths in
                                ~/.zshrc with this comma-separated list of
                                grep patterns for 'df -h' output.
                                Example: --filesystems "/dev/nvme0n1p2,/dev/sda1"

      --no-disk-info            Strip the 'df -h' disk-info lines from the
                                .zshrc personalization block entirely.

      --no-reboot               Don't prompt to reboot at the end.

      --skip-theme-gui          Don't launch nwg-look at the end (skip the
                                interactive GTK theme picker).

      --no-services             Don't install/enable the display manager
                                (SDDM) or enable NetworkManager/Bluetooth.
                                Useful in WSL or other headless contexts.

  -h, --help                    Show this help and exit.

If --filesystems / --no-disk-info aren't given, the default WSL/LVM paths
(/dev/mapper/volgroup0-lv_root, /dev/mapper/volgroup0-lv_home) are kept.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--filesystems)  FILESYSTEMS="${2:-}"; shift 2 ;;
    --no-disk-info)    NO_DISK_INFO=true; shift ;;
    --no-reboot)       NO_REBOOT=true; shift ;;
    --skip-theme-gui)  SKIP_THEME_GUI=true; shift ;;
    --no-services)     NO_SERVICES=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 printf '%sunknown option:%s %s\n' "$RED" "$RESET" "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$NO_DISK_INFO" == "true" && -n "$FILESYSTEMS" ]]; then
  printf '%s✗%s --filesystems and --no-disk-info are mutually exclusive\n' "$RED" "$RESET" >&2
  exit 2
fi

# ─── sanity checks ────────────────────────────────────────────────────────────
banner

[[ $EUID -ne 0 ]] || die "Don't run this as root. Run as your normal user; sudo will be invoked when needed."
[[ -f /etc/arch-release ]] || die "This script is for Arch Linux (or an Arch-based distro). /etc/arch-release not found."
command -v sudo >/dev/null || die "sudo is required but not installed."

info "Caching sudo credentials (you may be prompted once)…"
sudo -v
# keep sudo alive for the duration of the script
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ─── helpers ─────────────────────────────────────────────────────────────────

# Stow a package safely: back up any conflicting real files in $HOME first,
# then symlink the package's contents into $HOME.
safe_stow() {
  local pkg=$1
  [[ -d "$SCRIPT_DIR/$pkg" ]] || { warn "stow package '$pkg' not found, skipping"; return 0; }

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"

  # Back up any conflicting non-symlink files in $HOME
  while IFS= read -r -d '' src; do
    local rel="${src#"$SCRIPT_DIR/$pkg/"}"
    local target="$HOME/$rel"
    if [[ -e "$target" && ! -L "$target" ]]; then
      mkdir -p "$(dirname "$target")"
      mv "$target" "$target.backup.$ts"
      info "Backed up existing $target → $target.backup.$ts"
    fi
  done < <(find "$SCRIPT_DIR/$pkg" -type f -print0)

  # --restow is idempotent: unlink first, then re-link
  stow --restow --target="$HOME" --dir="$SCRIPT_DIR" "$pkg"
  ok "Stowed $pkg"
}

# ─── 1. update system ────────────────────────────────────────────────────────
step 1 "Synchronizing and upgrading system (pacman -Syu)"
sudo pacman -Syu --noconfirm
ok "System packages up to date"

# ─── 2. install base packages from official repos ────────────────────────────
step 2 "Installing base packages"
BASE_PKGS=(
  # tools this script itself needs
  git base-devel stow zsh fastfetch curl wget
  # handy CLI extras you'll inevitably want on a fresh box
  tree htop btop neovim tmux unzip zip
  ripgrep fd bat eza fzf jq
  github-cli openssh man-db less
  python-pip
)
sudo pacman -S --needed --noconfirm "${BASE_PKGS[@]}"
ok "Installed: ${BASE_PKGS[*]}"

# ─── 3. bootstrap yay (AUR helper) if missing ────────────────────────────────
step 3 "Setting up yay (AUR helper)"
if command -v yay >/dev/null; then
  ok "yay already installed"
else
  info "Bootstrapping yay-bin from the AUR"
  YAY_TMP="$(mktemp -d)"
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$YAY_TMP/yay-bin"
  ( cd "$YAY_TMP/yay-bin" && makepkg -si --noconfirm )
  rm -rf "$YAY_TMP"
  ok "yay installed"
fi

# ─── 4. install Hyprland desktop ecosystem + handy GUI apps ──────────────────
step 4 "Installing Hyprland desktop ecosystem"
DESKTOP_PKGS=(
  # Hyprland core + the supporting Wayland services it can't run without
  hyprland hyprpaper hyprlock          # window manager + wallpaper + lockscreen
  hyprpolkitagent                      # graphical sudo/auth prompts
  xdg-desktop-portal-hyprland          # screenshots, screen sharing, file pickers
  xdg-desktop-portal-gtk               # GTK portal backend (file pickers etc.)

  # Bar, launcher, terminal, file managers
  waybar wofi                          # status bar + app launcher
  kitty                                # terminal
  nautilus                             # file manager — referenced as $fileManager in hyprland.conf
  thunar                               # secondary file manager

  # GTK theming
  nwg-look                             # GTK theme picker
  catppuccin-gtk-theme-mocha           # GTK theme (AUR)

  # Fonts (CJK added so non-Latin glyphs render in waybar/kitty/firefox)
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk

  # Audio stack — without PipeWire there's no sound, and wpctl (used by
  # XF86Audio* keybinds in hyprland.conf) ships with wireplumber.
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

  # Display manager (chosen during setup: SDDM defaulting to Hyprland)
  sddm

  # Networking — applet referenced by hyprland.conf via `exec-once = nm-applet`
  networkmanager network-manager-applet

  # Bluetooth
  bluez bluez-utils blueman

  # Wayland desktop utilities referenced by hyprland.conf
  swaync                               # AUR — notification daemon (exec-once = swaync)
  hyprshot                             # AUR — screenshots (PRINT keybinds)
  grim slurp wl-clipboard              # screenshot/region/clipboard backends
  brightnessctl playerctl numlockx     # XF86 brightness / media / numlockx keybinds

  # Qt Wayland integration — without these, Qt apps fall back to XWayland or crash
  qt5-wayland qt6-wayland

  # GUI apps you'll inevitably want
  firefox                              # web browser
  vlc                                  # media player
  discord                              # chat
)
yay -S --needed --noconfirm "${DESKTOP_PKGS[@]}"
ok "Installed ${#DESKTOP_PKGS[@]} desktop packages (hyprland + portals + audio + DM + apps)"

# ─── 5. install Oh My Zsh + plugins ──────────────────────────────────────────
step 5 "Installing Oh My Zsh and plugins"
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
if [[ -d "$ZSH" ]]; then
  ok "Oh My Zsh already present at $ZSH"
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  ok "Oh My Zsh installed"
fi

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

# ─── 6. stow all dotfiles + personalize .zshrc ───────────────────────────────
step 6 "Stowing dotfiles into \$HOME"

# Stow the .zshrc (the repo keeps it at arch/.zshrc, not in a stow package, so
# we copy it directly with a timestamped backup of any existing one).
DST_ZSHRC="$HOME/.zshrc"
SRC_ZSHRC="$SCRIPT_DIR/.zshrc"
[[ -f "$SRC_ZSHRC" ]] || die "Could not find $SRC_ZSHRC next to this script."

if [[ -f "$DST_ZSHRC" ]] && ! cmp -s "$SRC_ZSHRC" "$DST_ZSHRC"; then
  BACKUP="$DST_ZSHRC.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$DST_ZSHRC" "$BACKUP"
  info "Backed up existing .zshrc → $BACKUP"
fi
cp "$SRC_ZSHRC" "$DST_ZSHRC"
ok ".zshrc installed at $DST_ZSHRC"

# Personalize the disk-info block based on flags
if [[ "$NO_DISK_INFO" == "true" ]]; then
  sed -i "/^df -h | GREP_COLORS='mt=1;36' grep/d" "$DST_ZSHRC"
  info "Stripped all 'df -h' disk-info lines from .zshrc"
elif [[ -n "$FILESYSTEMS" ]]; then
  replacement=""
  IFS=',' read -ra _FS_ARR <<< "$FILESYSTEMS"
  for fs in "${_FS_ARR[@]}"; do
    fs="${fs# }"; fs="${fs% }"
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

# Stow the rest. Order matters only insofar as conflicting paths matter; all
# of these target distinct directories under ~/.config so order is fine.
STOW_PKGS=(backgrounds hyprpaper hyprlock hyprmocha hyprland kitty waybar wofi)
for pkg in "${STOW_PKGS[@]}"; do
  safe_stow "$pkg"
done

# waybar is a special case: if it's currently running, restart it so it picks
# up the new config. Don't fail if it's not running.
if pgrep -x waybar >/dev/null; then
  pkill -x waybar 2>/dev/null || true
  info "Killed running waybar instance (it'll be respawned by hyprland)"
fi

# ─── 7. set zsh as default shell ─────────────────────────────────────────────
step 7 "Setting zsh as the default shell"
ZSH_BIN="$(command -v zsh)"

if ! grep -qxF "$ZSH_BIN" /etc/shells; then
  echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  info "Added $ZSH_BIN to /etc/shells"
fi

if getent passwd "$USER" | cut -d: -f7 | grep -qxF "$ZSH_BIN"; then
  ok "zsh is already the default shell"
else
  sudo chsh -s "$ZSH_BIN" "$USER"
  ok "Default shell set to $ZSH_BIN (takes effect on next login)"
fi

# ─── 8. enable system services + pin SDDM default session to Hyprland ───────
step 8 "Enabling system services"
if [[ "$NO_SERVICES" == "true" ]]; then
  info "Skipping services step (--no-services)"
else
  enable_service() {
    local svc=$1
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      ok "$svc already enabled"
    else
      sudo systemctl enable "$svc" >/dev/null
      ok "Enabled $svc"
    fi
  }

  enable_service NetworkManager.service
  enable_service bluetooth.service

  # If GDM is the currently-enabled display manager (e.g. GNOME was installed
  # via archinstall), disable it before enabling SDDM — only one DM can hold
  # display-manager.service at a time.
  if systemctl is-enabled --quiet gdm.service 2>/dev/null; then
    sudo systemctl disable gdm.service >/dev/null
    info "Disabled gdm.service (SDDM will take over as the display manager)"
  fi

  enable_service sddm.service

  # Pre-seed SDDM's per-user "last session" so the login screen lands on
  # Hyprland by default. SDDM remembers the last selection on subsequent
  # logins, so this only matters for the first boot after running the script.
  sudo install -d -o sddm -g sddm -m 0755 /var/lib/sddm 2>/dev/null || \
    sudo install -d -m 0755 /var/lib/sddm
  sudo tee /var/lib/sddm/state.conf >/dev/null <<EOF
[Last]
Session=hyprland.desktop
User=$USER
EOF
  sudo chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true
  ok "SDDM default session pinned to Hyprland for $USER"
fi

# ─── done ────────────────────────────────────────────────────────────────────
printf '\n%s╭─────────────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
printf '%s│              all done — enjoy!              │%s\n' "$GREEN" "$RESET"
printf '%s╰─────────────────────────────────────────────╯%s\n\n' "$GREEN" "$RESET"

# ─── optional: GTK theme picker ──────────────────────────────────────────────
if [[ "$SKIP_THEME_GUI" == "true" ]]; then
  info "Skipping nwg-look (use it later to pick a GTK theme: nwg-look)"
else
  read -r -p "Launch nwg-look now to pick a GTK theme? [y/N] " ans
  case "${ans,,}" in
    y|yes) nwg-look || warn "nwg-look exited non-zero (no display server?)" ;;
    *)     info "Skipped. Run 'nwg-look' anytime to pick a theme." ;;
  esac
fi

# ─── optional: reboot ────────────────────────────────────────────────────────
if [[ "$NO_REBOOT" == "true" ]]; then
  info "Skipping reboot. You may want to reboot or relog to enter the new session."
else
  read -r -p "$(printf '%sReboot now?%s [y/N] ' "$BOLD" "$RESET")" ans
  case "${ans,,}" in
    y|yes) info "Rebooting…"; sudo reboot ;;
    *)     info "Not rebooting. Reboot manually when ready." ;;
  esac
fi
