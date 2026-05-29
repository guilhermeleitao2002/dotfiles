#!/usr/bin/env bash
#
# Generate an SSH key on this machine and register it with GitHub via the gh CLI.
# Safe to re-run.

# ─── ensure a capable bash ─────────────────────────────────────────────────────
# macOS still ships bash 3.2; this script uses associative arrays, mapfile and
# ${var,,}, all of which need bash >= 4. Re-exec under a newer bash if we can
# find one, otherwise fail with a clear hint.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for _bash in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash bash; do
    _bash="$(command -v "$_bash" 2>/dev/null)" || continue
    [ -x "$_bash" ] || continue
    _ver="$("$_bash" -c 'printf %s "${BASH_VERSINFO:-0}"' 2>/dev/null)"
    case "$_ver" in ''|*[!0-9]*) continue ;; esac
    [ "$_ver" -ge 4 ] && exec "$_bash" "$0" "$@"
  done
  echo "error: this script requires bash >= 4 (found ${BASH_VERSION:-non-bash}). Install a newer bash, e.g. 'brew install bash'." >&2
  exit 1
fi

set -euo pipefail

# ─── pretty output ────────────────────────────────────────────────────────────
BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
CYAN=$'\e[1;36m'; GREEN=$'\e[1;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[1;31m'; MAGENTA=$'\e[1;35m'

# Use UTF-8 glyphs only when the locale can render them; fall back to ASCII so
# output stays readable on a box whose locale is still C/POSIX (common on a
# fresh install before locales are generated).
if printf '%s' "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" | grep -qiE 'utf-?8'; then
  UNICODE=true
  G_OK='✓'; G_INFO='·'; G_WARN='!'; G_ERR='✗'; G_ARROW='==>'
else
  UNICODE=false
  G_OK='+'; G_INFO='-'; G_WARN='!'; G_ERR='x'; G_ARROW='==>'
fi

step()  { printf '\n%s%s%s %s[%d/%d]%s %s%s%s\n' "$CYAN" "$G_ARROW" "$RESET" "$DIM" "$1" "$TOTAL_STEPS" "$RESET" "$BOLD" "$2" "$RESET"; }
ok()    { printf '  %s%s%s %s\n' "$GREEN" "$G_OK" "$RESET" "$1"; }
info()  { printf '  %s%s%s %s\n' "$DIM" "$G_INFO" "$RESET" "$1"; }
warn()  { printf '  %s%s%s %s\n' "$YELLOW" "$G_WARN" "$RESET" "$1"; }
die()   { printf '\n%s%s%s %s\n' "$RED" "$G_ERR" "$RESET" "$1" >&2; exit 1; }

banner() {
  printf '\n%s' "$MAGENTA"
  if [[ "$UNICODE" == true ]]; then
    cat <<'EOF'
  ╭─────────────────────────────────────────────╮
  │   gleitao · github ssh key bootstrap        │
  ╰─────────────────────────────────────────────╯
EOF
  else
    cat <<'EOF'
  +---------------------------------------------+
  |   gleitao - github ssh key bootstrap        |
  +---------------------------------------------+
EOF
  fi
  printf '%s\n' "$RESET"
}

TOTAL_STEPS=6

# ─── defaults & argument parsing ──────────────────────────────────────────────
# Derive a short hostname/user without relying on the `hostname` binary, which
# isn't installed by default on minimal systems (e.g. fresh Arch). uname is part
# of coreutils and is always present; $HOSTNAME is empty in non-interactive bash.
HOSTNAME_SHORT="${HOSTNAME:-}"
[[ -n "$HOSTNAME_SHORT" ]] || HOSTNAME_SHORT="$(uname -n 2>/dev/null || echo localhost)"
HOSTNAME_SHORT="${HOSTNAME_SHORT%%.*}"
USER_NAME="${USER:-$(id -un 2>/dev/null || echo user)}"
DEFAULT_TITLE="${USER_NAME}@${HOSTNAME_SHORT}"

KEY_TYPE="ed25519"
KEY_FILE=""
KEY_TITLE="$DEFAULT_TITLE"
KEY_EMAIL=""
NO_PASSPHRASE=false
ADD_SIGNING_KEY=false
FORCE=false
SKIP_VERIFY=false
NO_INSTALL=false
ASSUME_YES=false

usage() {
  cat <<EOF
${BOLD}usage:${RESET} $(basename "$0") [options]

  -t, --type <ed25519|rsa>   SSH key type (default: ed25519).
  -f, --file <path>          Private key path (default: ~/.ssh/id_<type>).
      --title <text>         Title shown in GitHub → Settings → SSH keys
                             (default: "${DEFAULT_TITLE}").
  -e, --email <addr>         Email used as the key comment
                             (default: git config user.email, else
                             "${USER_NAME}@${HOSTNAME_SHORT}").
      --no-passphrase        Generate the key with an empty passphrase
                             (default: ssh-keygen prompts interactively).
      --signing-key          Also register the key as a GitHub signing key
                             (in addition to the default auth key).
      --force                Overwrite an existing key file without asking.
      --skip-verify          Don't try 'ssh -T git@github.com' at the end.
      --no-install           Don't try to install missing tools — just fail.
  -y, --yes                  Skip the install confirmation prompt.

  -h, --help                 Show this help and exit.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--type)         KEY_TYPE="${2:-}"; shift 2 ;;
    -f|--file)         KEY_FILE="${2:-}"; shift 2 ;;
       --title)        KEY_TITLE="${2:-}"; shift 2 ;;
    -e|--email)        KEY_EMAIL="${2:-}"; shift 2 ;;
       --no-passphrase) NO_PASSPHRASE=true; shift ;;
       --signing-key)  ADD_SIGNING_KEY=true; shift ;;
       --force)        FORCE=true; shift ;;
       --skip-verify)  SKIP_VERIFY=true; shift ;;
       --no-install)   NO_INSTALL=true; shift ;;
    -y|--yes)          ASSUME_YES=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 printf '%sunknown option:%s %s\n' "$RED" "$RESET" "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$KEY_TYPE" in
  ed25519|rsa) ;;
  *) die "Unsupported --type '$KEY_TYPE'. Use ed25519 or rsa." ;;
esac

[[ -n "$KEY_FILE" ]]  || KEY_FILE="$HOME/.ssh/id_${KEY_TYPE}"
[[ -n "$KEY_TITLE" ]] || die "--title cannot be empty."

PUB_FILE="${KEY_FILE}.pub"

# ─── sanity checks ────────────────────────────────────────────────────────────
banner

[[ $EUID -ne 0 ]] || die "Don't run this as root. SSH keys belong to your user account."

TOTAL_STEPS=6

# ─── 1. tooling present ──────────────────────────────────────────────────────
step 1 "Checking required tools"

# ── package-manager auto-install ─────────────────────────────────────────────
PKG_MGR=""
detect_pkg_mgr() {
  if   command -v pacman  >/dev/null; then PKG_MGR=pacman
  elif command -v apt-get >/dev/null; then PKG_MGR=apt
  elif command -v dnf     >/dev/null; then PKG_MGR=dnf
  elif command -v zypper  >/dev/null; then PKG_MGR=zypper
  elif command -v brew    >/dev/null; then PKG_MGR=brew
  else PKG_MGR=""
  fi
}

# Map a missing tool name → the package name for the detected manager.
pkg_for() {
  local tool="$1"
  case "$PKG_MGR:$tool" in
    pacman:ssh|pacman:ssh-keygen) echo openssh ;;
    apt:ssh|apt:ssh-keygen)       echo openssh-client ;;
    dnf:ssh|dnf:ssh-keygen)       echo openssh-clients ;;
    zypper:ssh|zypper:ssh-keygen) echo openssh-clients ;;
    brew:ssh|brew:ssh-keygen)     echo openssh ;;
    pacman:gh)                    echo github-cli ;;
    *:*)                          echo "$tool" ;;
  esac
}

SUDO=""
need_sudo() {
  [[ "$PKG_MGR" == "brew" || $EUID -eq 0 ]] && { SUDO=""; return; }
  if   command -v sudo >/dev/null; then SUDO="sudo"
  elif command -v doas >/dev/null; then SUDO="doas"
  else die "Need root to install packages but neither 'sudo' nor 'doas' is installed. Re-run as root or install one."
  fi
}

install_packages() {
  local pkgs=("$@")
  need_sudo
  case "$PKG_MGR" in
    pacman) $SUDO pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y "${pkgs[@]}" ;;
    dnf)    $SUDO dnf install -y "${pkgs[@]}" ;;
    zypper) $SUDO zypper --non-interactive install "${pkgs[@]}" ;;
    brew)   brew install "${pkgs[@]}" ;;
    *)      return 1 ;;
  esac
}

REQUIRED=(ssh-keygen ssh gh git)
MISSING=()
for cmd in "${REQUIRED[@]}"; do
  command -v "$cmd" >/dev/null || MISSING+=("$cmd")
done

if (( ${#MISSING[@]} > 0 )); then
  detect_pkg_mgr
  if [[ -z "$PKG_MGR" ]]; then
    printf '\n%s%s%s Missing tools and no known package manager (pacman/apt/dnf/zypper/brew) detected.\n' "$RED" "$G_ERR" "$RESET" >&2
    printf '  Required: %s\n' "${MISSING[*]}" >&2
    exit 1
  fi
  if [[ "$NO_INSTALL" == "true" ]]; then
    die "Missing tools (${MISSING[*]}) but --no-install was set."
  fi

  # Dedup packages (ssh + ssh-keygen → same package).
  declare -A SEEN=()
  TO_INSTALL=()
  for t in "${MISSING[@]}"; do
    pkg="$(pkg_for "$t")"
    if [[ -z "${SEEN[$pkg]:-}" ]]; then
      SEEN[$pkg]=1
      TO_INSTALL+=("$pkg")
    fi
  done

  info "Detected package manager: ${BOLD}${PKG_MGR}${RESET}"
  warn "Missing tools: ${MISSING[*]}"
  info "Will install: ${BOLD}${TO_INSTALL[*]}${RESET}"

  if [[ "$ASSUME_YES" != "true" ]]; then
    read -r -p "  Proceed with install? [Y/n] " ans
    case "${ans,,}" in
      n|no) die "Aborted — install the listed tools manually and re-run." ;;
    esac
  fi

  if ! install_packages "${TO_INSTALL[@]}"; then
    warn "Package install command exited non-zero — some tools may still be missing."
    if [[ "$PKG_MGR" == "apt" ]] && [[ " ${TO_INSTALL[*]} " == *" gh "* ]]; then
      cat >&2 <<EOF

  ${YELLOW}Note:${RESET} on older Debian/Ubuntu releases, 'gh' isn't in the default repos.
  Follow the official instructions to add the GitHub CLI apt repo:

    https://cli.github.com/manual/installation

EOF
    fi
  fi

  STILL_MISSING=()
  for cmd in "${REQUIRED[@]}"; do
    command -v "$cmd" >/dev/null || STILL_MISSING+=("$cmd")
  done
  (( ${#STILL_MISSING[@]} == 0 )) || die "Still missing after install: ${STILL_MISSING[*]}"
fi
ok "openssh available ($(ssh -V 2>&1))"
ok "gh available ($(gh --version | head -n1))"
ok "git available ($(git --version))"

# ─── 2. gh authentication ─────────────────────────────────────────────────────
step 2 "Checking GitHub CLI authentication"

# gh auth status writes to stderr; capture both streams.
if AUTH_STATUS="$(gh auth status 2>&1)"; then
  GH_USER="$(gh api user --jq .login 2>/dev/null || echo 'unknown')"
  ok "Authenticated as ${BOLD}${GH_USER}${RESET}"
else
  printf '\n%s%s%s You are not signed in to GitHub via the gh CLI.\n\n' "$RED" "$G_ERR" "$RESET" >&2
  cat >&2 <<EOF
  Run:

    ${BOLD}gh auth login${RESET}

  Pick:
    - GitHub.com
    - SSH or HTTPS (either works for this script; HTTPS is simpler)
    - Authenticate via web browser (recommended)

  When 'gh auth status' shows a green check, re-run this script.

  Tip: this script needs the 'admin:public_key' scope to register SSH keys,
       and 'admin:ssh_signing_key' if you use --signing-key. If gh later
       complains about missing scopes, run:

    ${BOLD}gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key${RESET}

EOF
  exit 1
fi

# ─── 3. generate the key ──────────────────────────────────────────────────────
step 3 "Generating SSH key (${BOLD}${KEY_TYPE}${RESET}) at ${KEY_FILE}"

mkdir -p "$(dirname "$KEY_FILE")"
chmod 700 "$(dirname "$KEY_FILE")"

if [[ -e "$KEY_FILE" || -e "$PUB_FILE" ]]; then
  if [[ "$FORCE" == "true" ]]; then
    warn "Overwriting existing key at $KEY_FILE (--force)"
    rm -f "$KEY_FILE" "$PUB_FILE"
  else
    warn "A key already exists at $KEY_FILE"
    read -r -p "  Overwrite it? [y/N] " ans
    case "${ans,,}" in
      y|yes)
        rm -f "$KEY_FILE" "$PUB_FILE"
        info "Old key removed"
        ;;
      *)
        info "Keeping the existing key — will reuse its public half for the GitHub step."
        ;;
    esac
  fi
fi

if [[ ! -e "$KEY_FILE" ]]; then
  # Resolve the email used as the key comment.
  if [[ -z "$KEY_EMAIL" ]]; then
    KEY_EMAIL="$(git config --get user.email 2>/dev/null || true)"
    [[ -n "$KEY_EMAIL" ]] || KEY_EMAIL="${USER_NAME}@${HOSTNAME_SHORT}"
  fi

  KEYGEN_ARGS=(-t "$KEY_TYPE" -f "$KEY_FILE" -C "$KEY_EMAIL")
  [[ "$KEY_TYPE" == "rsa" ]] && KEYGEN_ARGS+=(-b 4096)
  [[ "$NO_PASSPHRASE" == "true" ]] && KEYGEN_ARGS+=(-N "")

  info "Comment: $KEY_EMAIL"
  if [[ "$NO_PASSPHRASE" == "true" ]]; then
    info "Generating without a passphrase"
  else
    info "ssh-keygen will prompt for a passphrase (press Enter twice for none)"
  fi
  ssh-keygen "${KEYGEN_ARGS[@]}"
  ok "Key generated"
else
  ok "Reusing existing key"
fi

chmod 600 "$KEY_FILE"
chmod 644 "$PUB_FILE"

# ─── 4. add to ssh-agent ──────────────────────────────────────────────────────
step 4 "Adding the key to ssh-agent"

# Start an agent for this session if there isn't one.
if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l >/dev/null 2>&1; then
  if command -v ssh-agent >/dev/null; then
    info "No running ssh-agent detected — starting one for this session"
    eval "$(ssh-agent -s)" >/dev/null
  else
    warn "ssh-agent not found; skipping. Your key will still work via ~/.ssh/config defaults."
  fi
fi

if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  if ssh-add -l 2>/dev/null | awk '{print $3}' | grep -qxF "$KEY_FILE"; then
    ok "Key already loaded in ssh-agent"
  else
    if ssh-add "$KEY_FILE"; then
      ok "Key added to ssh-agent"
    else
      warn "Could not add the key to ssh-agent (passphrase mismatch? agent down?). Continuing."
    fi
  fi
else
  info "No ssh-agent available in this shell. You can add the key later with: ssh-add $KEY_FILE"
fi

# ─── 5. register on GitHub ────────────────────────────────────────────────────
step 5 "Registering the public key on GitHub"

PUB_CONTENT="$(awk '{print $1, $2}' "$PUB_FILE")"  # type + base64 body (no comment)

# Auth key registration ───────────────────────────────────────────
EXISTING_AUTH_KEYS="$(gh api /user/keys --jq '.[] | "\(.title)\t\(.key)"' 2>/dev/null || true)"
if printf '%s\n' "$EXISTING_AUTH_KEYS" | awk -F'\t' -v k="$PUB_CONTENT" '$2 == k {found=1} END {exit !found}'; then
  EXISTING_TITLE="$(printf '%s\n' "$EXISTING_AUTH_KEYS" | awk -F'\t' -v k="$PUB_CONTENT" '$2 == k {print $1; exit}')"
  ok "Auth key already on GitHub (title: ${EXISTING_TITLE})"
elif printf '%s\n' "$EXISTING_AUTH_KEYS" | awk -F'\t' -v t="$KEY_TITLE" '$1 == t {found=1} END {exit !found}'; then
  die "A different key with title '${KEY_TITLE}' already exists on GitHub. Pass --title to choose a unique one."
else
  if gh ssh-key add "$PUB_FILE" --title "$KEY_TITLE" >/dev/null; then
    ok "Auth key added to GitHub as '${BOLD}${KEY_TITLE}${RESET}'"
  else
    die "Failed to add auth key. If gh reports a missing scope, run: gh auth refresh -h github.com -s admin:public_key"
  fi
fi

# Signing key registration (optional) ─────────────────────────────
if [[ "$ADD_SIGNING_KEY" == "true" ]]; then
  EXISTING_SIGN_KEYS="$(gh api /user/ssh_signing_keys --jq '.[] | "\(.title)\t\(.key)"' 2>/dev/null || true)"
  if printf '%s\n' "$EXISTING_SIGN_KEYS" | awk -F'\t' -v k="$PUB_CONTENT" '$2 == k {found=1} END {exit !found}'; then
    EXISTING_TITLE="$(printf '%s\n' "$EXISTING_SIGN_KEYS" | awk -F'\t' -v k="$PUB_CONTENT" '$2 == k {print $1; exit}')"
    ok "Signing key already on GitHub (title: ${EXISTING_TITLE})"
  elif printf '%s\n' "$EXISTING_SIGN_KEYS" | awk -F'\t' -v t="$KEY_TITLE" '$1 == t {found=1} END {exit !found}'; then
    warn "A different signing key with title '${KEY_TITLE}' already exists; skipping. Use --title to pick a unique one."
  else
    if gh ssh-key add "$PUB_FILE" --title "$KEY_TITLE" --type signing >/dev/null; then
      ok "Signing key added to GitHub as '${BOLD}${KEY_TITLE}${RESET}'"
    else
      warn "Failed to add signing key. If gh reports a missing scope, run: gh auth refresh -h github.com -s admin:ssh_signing_key"
    fi
  fi
fi

# ─── 6. verify ────────────────────────────────────────────────────────────────
step 6 "Verifying SSH access to github.com"

if [[ "$SKIP_VERIFY" == "true" ]]; then
  info "Skipped (--skip-verify)"
else
  # `ssh -T git@github.com` exits 1 even on success — grep the message instead.
  # -o StrictHostKeyChecking=accept-new auto-accepts github's host key on first run.
  if VERIFY_OUT="$(ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "$KEY_FILE" -o IdentitiesOnly=yes git@github.com 2>&1)" || true; then
    if printf '%s' "$VERIFY_OUT" | grep -q "successfully authenticated"; then
      GH_LOGIN_FROM_SSH="$(printf '%s' "$VERIFY_OUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')"
      ok "GitHub recognized the key as ${BOLD}${GH_LOGIN_FROM_SSH:-$GH_USER}${RESET}"
    else
      warn "Did not get the expected 'successfully authenticated' banner from GitHub."
      printf '%s\n' "$VERIFY_OUT" | sed 's/^/      /'
      info "GitHub sometimes takes a few seconds to propagate a new key — try again with: ssh -T git@github.com"
    fi
  fi
fi

# ─── done ────────────────────────────────────────────────────────────────────
if [[ "$UNICODE" == true ]]; then
  printf '\n%s╭─────────────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
  printf '%s│              all done — enjoy!              │%s\n' "$GREEN" "$RESET"
  printf '%s╰─────────────────────────────────────────────╯%s\n\n' "$GREEN" "$RESET"
else
  printf '\n%s+---------------------------------------------+%s\n' "$GREEN" "$RESET"
  printf '%s|              all done - enjoy!              |%s\n' "$GREEN" "$RESET"
  printf '%s+---------------------------------------------+%s\n\n' "$GREEN" "$RESET"
fi

printf '  Key file       : %s\n' "$KEY_FILE"
printf '  Public key     : %s\n' "$PUB_FILE"
printf '  GitHub title   : %s\n' "$KEY_TITLE"
printf '  Signing key    : %s\n' "$([[ "$ADD_SIGNING_KEY" == "true" ]] && echo yes || echo no)"
printf '\n  Test anytime with: %sssh -T git@github.com%s\n\n' "$BOLD" "$RESET"
