#!/usr/bin/env bash
#
# Generate an SSH key on this machine and register it with GitHub via the gh CLI.
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
  │   gleitao · github ssh key bootstrap        │
  ╰─────────────────────────────────────────────╯
EOF
  printf '%s\n' "$RESET"
}

TOTAL_STEPS=6

# ─── defaults & argument parsing ──────────────────────────────────────────────
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
DEFAULT_TITLE="${USER}@${HOSTNAME_SHORT}"

KEY_TYPE="ed25519"
KEY_FILE=""
KEY_TITLE="$DEFAULT_TITLE"
KEY_EMAIL=""
NO_PASSPHRASE=false
ADD_SIGNING_KEY=false
FORCE=false
SKIP_VERIFY=false

usage() {
  cat <<EOF
${BOLD}usage:${RESET} $(basename "$0") [options]

  -t, --type <ed25519|rsa>   SSH key type (default: ed25519).
  -f, --file <path>          Private key path (default: ~/.ssh/id_<type>).
      --title <text>         Title shown in GitHub → Settings → SSH keys
                             (default: "${DEFAULT_TITLE}").
  -e, --email <addr>         Email used as the key comment
                             (default: git config user.email, else
                             "${USER}@${HOSTNAME_SHORT}").
      --no-passphrase        Generate the key with an empty passphrase
                             (default: ssh-keygen prompts interactively).
      --signing-key          Also register the key as a GitHub signing key
                             (in addition to the default auth key).
      --force                Overwrite an existing key file without asking.
      --skip-verify          Don't try 'ssh -T git@github.com' at the end.

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

MISSING=()
for cmd in ssh-keygen ssh; do
  command -v "$cmd" >/dev/null || MISSING+=("$cmd")
done
((${#MISSING[@]} == 0)) || die "Missing required tools: ${MISSING[*]} — install openssh and re-run."
ok "openssh available ($(ssh -V 2>&1))"

if ! command -v gh >/dev/null; then
  printf '\n%s✗%s GitHub CLI ('gh') is not installed.\n' "$RED" "$RESET" >&2
  cat >&2 <<EOF

  Install it, then re-run this script:

    ${BOLD}Arch / Manjaro${RESET}      sudo pacman -S github-cli
    ${BOLD}Debian / Ubuntu${RESET}     sudo apt install gh
                          (or follow https://cli.github.com/manual/installation)
    ${BOLD}Fedora${RESET}              sudo dnf install gh
    ${BOLD}macOS (Homebrew)${RESET}    brew install gh

EOF
  exit 1
fi
ok "gh available ($(gh --version | head -n1))"

# ─── 2. gh authentication ─────────────────────────────────────────────────────
step 2 "Checking GitHub CLI authentication"

# gh auth status writes to stderr; capture both streams.
if AUTH_STATUS="$(gh auth status 2>&1)"; then
  GH_USER="$(gh api user --jq .login 2>/dev/null || echo 'unknown')"
  ok "Authenticated as ${BOLD}${GH_USER}${RESET}"
else
  printf '\n%s✗%s You are not signed in to GitHub via the gh CLI.\n\n' "$RED" "$RESET" >&2
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
    [[ -n "$KEY_EMAIL" ]] || KEY_EMAIL="${USER}@${HOSTNAME_SHORT}"
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
printf '\n%s╭─────────────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
printf '%s│              all done — enjoy!              │%s\n' "$GREEN" "$RESET"
printf '%s╰─────────────────────────────────────────────╯%s\n\n' "$GREEN" "$RESET"

printf '  Key file       : %s\n' "$KEY_FILE"
printf '  Public key     : %s\n' "$PUB_FILE"
printf '  GitHub title   : %s\n' "$KEY_TITLE"
printf '  Signing key    : %s\n' "$([[ "$ADD_SIGNING_KEY" == "true" ]] && echo yes || echo no)"
printf '\n  Test anytime with: %sssh -T git@github.com%s\n\n' "$BOLD" "$RESET"
