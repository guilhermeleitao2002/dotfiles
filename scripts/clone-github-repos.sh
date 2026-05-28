#!/usr/bin/env bash
#
# Fetch the current user's GitHub repositories and clone the selected ones
# into a directory of their choice. Safe to re-run.
#
# Companion to ./setup-github-ssh.sh — if SSH access is not yet working,
# this script will offer to run that one for you.

set -euo pipefail

# ─── pretty output ────────────────────────────────────────────────────────────
BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
CYAN=$'\e[1;36m'; GREEN=$'\e[1;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[1;31m'; MAGENTA=$'\e[1;35m'; BLUE=$'\e[1;34m'

step()  { printf '\n%s==>%s %s[%d/%d]%s %s%s%s\n' "$CYAN" "$RESET" "$DIM" "$1" "$TOTAL_STEPS" "$RESET" "$BOLD" "$2" "$RESET"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
info()  { printf '  %s·%s %s\n' "$DIM" "$RESET" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
die()   { printf '\n%s✗%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

banner() {
  printf '\n%s' "$MAGENTA"
  cat <<'EOF'
  ╭─────────────────────────────────────────────╮
  │   gleitao · github repo clone helper        │
  ╰─────────────────────────────────────────────╯
EOF
  printf '%s\n' "$RESET"
}

TOTAL_STEPS=6

# ─── defaults & argument parsing ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_SETUP_SCRIPT="${SCRIPT_DIR}/setup-github-ssh.sh"

DEST_DIR=""
PROTOCOL=""                # ssh | https — auto-detected if empty
INCLUDE_FORKS=false
INCLUDE_ARCHIVED=false
INCLUDE_PRIVATE=true
OWNER_FILTER=""            # if set, only repos under this owner
LIMIT=1000
PARALLEL=4
ASSUME_YES=false
SWITCH_ACCOUNT=false
NO_SSH_SETUP=false
NO_INSTALL=false
INSTALL_FZF=true

usage() {
  cat <<EOF
${BOLD}usage:${RESET} $(basename "$0") [options]

  -d, --dir <path>           Destination directory (default: prompt; suggested \$HOME).
      --protocol <ssh|https> Clone protocol (default: ssh if it works, else https).
      --owner <login|org>    Only list repos under this owner (default: your repos).
      --include-forks        Include forks (default: hidden).
      --include-archived     Include archived repos (default: hidden).
      --no-private           Hide private repos.
      --limit <n>            Max repos to fetch (default: ${LIMIT}).
      --parallel <n>         Parallel clone workers (default: ${PARALLEL}).
      --switch-account       Run 'gh auth switch' before listing.
      --no-ssh-setup         Don't offer to run setup-github-ssh.sh on SSH failure.
      --no-install           Don't try to install missing tools — just fail.
      --no-fzf               Skip auto-installing fzf (the picker fallback still works).
  -y, --yes                  Skip the final confirmation before cloning.
  -h, --help                 Show this help and exit.

${BOLD}selection syntax${RESET} (when fzf isn't installed):
  ${DIM}all${RESET}                       select every repo
  ${DIM}none${RESET}                      clear selection (you'll be re-prompted)
  ${DIM}1,3,5-8${RESET}                   indices and inclusive ranges
  ${DIM}/pattern${RESET}                  regex match against owner/name
  Repeat / mix freely; press Enter on an empty line to confirm.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)             DEST_DIR="${2:-}"; shift 2 ;;
       --protocol)        PROTOCOL="${2:-}"; shift 2 ;;
       --owner)           OWNER_FILTER="${2:-}"; shift 2 ;;
       --include-forks)   INCLUDE_FORKS=true; shift ;;
       --include-archived) INCLUDE_ARCHIVED=true; shift ;;
       --no-private)      INCLUDE_PRIVATE=false; shift ;;
       --limit)           LIMIT="${2:-}"; shift 2 ;;
       --parallel)        PARALLEL="${2:-}"; shift 2 ;;
       --switch-account)  SWITCH_ACCOUNT=true; shift ;;
       --no-ssh-setup)    NO_SSH_SETUP=true; shift ;;
       --no-install)      NO_INSTALL=true; shift ;;
       --no-fzf)          INSTALL_FZF=false; shift ;;
    -y|--yes)             ASSUME_YES=true; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) printf '%sunknown option:%s %s\n' "$RED" "$RESET" "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${PROTOCOL:-}" in
  ""|ssh|https) ;;
  *) die "Unsupported --protocol '$PROTOCOL'. Use ssh or https." ;;
esac

[[ "$LIMIT"     =~ ^[0-9]+$ ]] || die "--limit must be a positive integer."
[[ "$PARALLEL" =~ ^[0-9]+$ ]] || die "--parallel must be a positive integer."

# ─── sanity checks ────────────────────────────────────────────────────────────
banner

[[ $EUID -ne 0 ]] || die "Don't run this as root. Clone repos as your own user."

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

# Map a tool name → the package name for the detected manager.
pkg_for() {
  local tool="$1"
  case "$PKG_MGR:$tool" in
    pacman:ssh)  echo openssh ;;
    apt:ssh)     echo openssh-client ;;
    dnf:ssh)     echo openssh-clients ;;
    zypper:ssh)  echo openssh-clients ;;
    brew:ssh)    echo openssh ;;
    pacman:gh)   echo github-cli ;;
    *:*)         echo "$tool" ;;       # git, jq, gh (non-arch), fzf — same name everywhere
  esac
}

SUDO=""
need_sudo() {
  [[ "$PKG_MGR" == "brew" || $EUID -eq 0 ]] && { SUDO=""; return; }
  if command -v sudo >/dev/null; then SUDO="sudo"
  else die "Need root to install packages but 'sudo' isn't installed. Re-run as root or install sudo."
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

REQUIRED=(git ssh gh jq)
MISSING_REQUIRED=()
for cmd in "${REQUIRED[@]}"; do
  command -v "$cmd" >/dev/null || MISSING_REQUIRED+=("$cmd")
done

MISSING_OPTIONAL=()
if [[ "$INSTALL_FZF" == "true" ]] && ! command -v fzf >/dev/null; then
  MISSING_OPTIONAL+=(fzf)
fi

if (( ${#MISSING_REQUIRED[@]} + ${#MISSING_OPTIONAL[@]} > 0 )); then
  detect_pkg_mgr
  if [[ -z "$PKG_MGR" ]]; then
    printf '\n%s✗%s Missing tools and no known package manager (pacman/apt/dnf/zypper/brew) detected.\n' "$RED" "$RESET" >&2
    printf '  Required: %s\n' "${MISSING_REQUIRED[*]:-none}" >&2
    (( ${#MISSING_OPTIONAL[@]} )) && printf '  Optional: %s\n' "${MISSING_OPTIONAL[*]}" >&2
    exit 1
  fi
  if [[ "$NO_INSTALL" == "true" ]]; then
    die "Missing tools (${MISSING_REQUIRED[*]} ${MISSING_OPTIONAL[*]}) but --no-install was set."
  fi

  TO_INSTALL=()
  for t in "${MISSING_REQUIRED[@]}" "${MISSING_OPTIONAL[@]}"; do
    TO_INSTALL+=("$(pkg_for "$t")")
  done

  info "Detected package manager: ${BOLD}${PKG_MGR}${RESET}"
  (( ${#MISSING_REQUIRED[@]} )) && warn "Missing required: ${MISSING_REQUIRED[*]}"
  (( ${#MISSING_OPTIONAL[@]} )) && info "Missing optional: ${MISSING_OPTIONAL[*]} (fzf — nicer picker)"
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

  # Re-check.
  STILL_MISSING=()
  for cmd in "${REQUIRED[@]}"; do
    command -v "$cmd" >/dev/null || STILL_MISSING+=("$cmd")
  done
  (( ${#STILL_MISSING[@]} == 0 )) || die "Still missing after install: ${STILL_MISSING[*]}"
fi
ok "git, ssh, gh, jq available"

HAS_FZF=false
if command -v fzf >/dev/null; then
  HAS_FZF=true
  ok "fzf detected — multi-select will use it"
else
  info "fzf not installed — using numbered fallback selector"
fi

# ─── 2. gh authentication ─────────────────────────────────────────────────────
step 2 "Checking GitHub CLI authentication"

if [[ "$SWITCH_ACCOUNT" == "true" ]]; then
  info "Running 'gh auth switch'..."
  gh auth switch || warn "gh auth switch did not complete; continuing with current account."
fi

# Probe with an actual API call — auth status alone can lie about expired tokens.
if ! GH_USER="$(gh api user --jq .login 2>/dev/null)"; then
  printf '\n%s✗%s gh is not authenticated (or the active token is invalid).\n\n' "$RED" "$RESET" >&2
  if [[ "$ASSUME_YES" == "true" ]]; then
    die "Non-interactive run: refusing to launch 'gh auth login'. Authenticate first."
  fi
  cat >&2 <<EOF
  Run 'gh auth login' now? This will open the GitHub OAuth flow.
EOF
  read -r -p "  Launch 'gh auth login'? [Y/n] " ans
  case "${ans,,}" in
    n|no) die "Authenticate with 'gh auth login' and re-run this script." ;;
    *)    gh auth login || die "gh auth login failed." ;;
  esac
  GH_USER="$(gh api user --jq .login 2>/dev/null)" \
    || die "Still not authenticated after gh auth login. Aborting."
fi
ok "Authenticated as ${BOLD}${GH_USER}${RESET}"

# Show any other logged-in accounts so the user knows they can --switch-account.
OTHER_ACCOUNTS="$(gh auth status 2>&1 \
  | awk -v me="$GH_USER" '/account/ && $0 !~ me {for (i=1;i<=NF;i++) if ($i=="account") print $(i+1)}' \
  | sort -u || true)"
if [[ -n "$OTHER_ACCOUNTS" ]]; then
  info "Other accounts in gh: $(echo $OTHER_ACCOUNTS | tr '\n' ' ')(use --switch-account to swap)"
fi

# ─── 3. clone protocol ────────────────────────────────────────────────────────
step 3 "Choosing clone protocol"

ssh_works() {
  local out
  out="$(ssh -T -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=8 git@github.com 2>&1 || true)"
  [[ "$out" == *"successfully authenticated"* ]]
}

if [[ -z "$PROTOCOL" ]]; then
  info "Probing 'ssh -T git@github.com'..."
  if ssh_works; then
    PROTOCOL="ssh"
    ok "SSH access to github.com is working — using SSH"
  else
    warn "SSH to github.com did not authenticate."
    if [[ "$NO_SSH_SETUP" == "true" || "$ASSUME_YES" == "true" || ! -x "$SSH_SETUP_SCRIPT" ]]; then
      [[ -x "$SSH_SETUP_SCRIPT" ]] || info "setup-github-ssh.sh not found or not executable next to this script."
      PROTOCOL="https"
      info "Falling back to HTTPS (gh's credentials will be used)."
    else
      printf '  Run %ssetup-github-ssh.sh%s now to provision a key?\n' "$BOLD" "$RESET"
      read -r -p "  [Y/n] " ans
      case "${ans,,}" in
        n|no)
          PROTOCOL="https"
          info "Falling back to HTTPS."
          ;;
        *)
          bash "$SSH_SETUP_SCRIPT" || warn "setup-github-ssh.sh exited non-zero; will try SSH anyway."
          if ssh_works; then
            PROTOCOL="ssh"
            ok "SSH now works — using SSH"
          else
            PROTOCOL="https"
            warn "SSH still not working — falling back to HTTPS."
          fi
          ;;
      esac
    fi
  fi
elif [[ "$PROTOCOL" == "ssh" ]]; then
  if ssh_works; then
    ok "SSH access confirmed"
  else
    warn "You forced --protocol ssh, but ssh -T git@github.com is not authenticating. Cloning will likely fail."
  fi
else
  ok "Using HTTPS (gh credentials)"
fi

# ─── 4. fetch repo list ───────────────────────────────────────────────────────
step 4 "Fetching repositories from GitHub"

OWNER_FOR_LIST="${OWNER_FILTER:-$GH_USER}"
GH_LIST_ARGS=( "$OWNER_FOR_LIST" --limit "$LIMIT" --json nameWithOwner,sshUrl,url,isPrivate,isFork,isArchived,description,primaryLanguage,updatedAt,stargazerCount,diskUsage )
[[ "$INCLUDE_FORKS"    == "false" ]] && GH_LIST_ARGS+=( --no-archived ) || true
# `gh repo list` has --no-archived and --fork / --source / --archived filters, but
# they're mutually exclusive in subtle ways. Pull everything and filter in jq instead.

info "Owner: ${BOLD}${OWNER_FOR_LIST}${RESET} · limit ${LIMIT}"
RAW_JSON="$(gh repo list "$OWNER_FOR_LIST" --limit "$LIMIT" \
  --json nameWithOwner,sshUrl,url,isPrivate,isFork,isArchived,description,primaryLanguage,updatedAt,stargazerCount,diskUsage)" \
  || die "gh repo list failed for owner '$OWNER_FOR_LIST'."

# Build a TSV: nameWithOwner \t sshUrl \t httpsUrl \t visibility \t lang \t stars \t updatedAt \t description
TSV="$(printf '%s' "$RAW_JSON" | jq -r --argjson forks "$INCLUDE_FORKS" \
                                          --argjson archived "$INCLUDE_ARCHIVED" \
                                          --argjson private "$INCLUDE_PRIVATE" '
  sort_by(.updatedAt) | reverse
  | map(select(($forks    or (.isFork    | not))
            and ($archived or (.isArchived | not))
            and ($private  or (.isPrivate  | not))))
  | .[]
  | [
      .nameWithOwner,
      .sshUrl,
      .url,
      (if .isPrivate then "private" else "public" end) + (if .isArchived then ",archived" else "" end) + (if .isFork then ",fork" else "" end),
      (.primaryLanguage.name // "-"),
      (.stargazerCount | tostring),
      (.updatedAt | sub("T.*"; "")),
      ((.description // "") | gsub("\t"; " ") | gsub("\n"; " "))
    ]
  | @tsv
')"

if [[ -z "$TSV" ]]; then
  die "No repositories matched the current filters for '$OWNER_FOR_LIST'."
fi

mapfile -t REPO_LINES <<<"$TSV"
REPO_COUNT=${#REPO_LINES[@]}
ok "Fetched ${BOLD}${REPO_COUNT}${RESET} repositories"

# ─── 5. interactive selection ─────────────────────────────────────────────────
step 5 "Selecting repositories to clone"

# Pre-format display lines (index + summary) used by both pickers.
DISPLAY_LINES=()
for i in "${!REPO_LINES[@]}"; do
  IFS=$'\t' read -r name _ssh _https vis lang stars updated desc <<<"${REPO_LINES[$i]}"
  idx=$(printf '%3d' $((i+1)))
  meta="$(printf '%s · %s · ⭐%s · %s' "$vis" "$lang" "$stars" "$updated")"
  trimmed_desc="${desc}"
  (( ${#trimmed_desc} > 70 )) && trimmed_desc="${trimmed_desc:0:67}..."
  DISPLAY_LINES+=("${idx}  $(printf '%-45s' "$name")  ${DIM}${meta}${RESET}  ${trimmed_desc}")
done

SELECTED_INDICES=()

if [[ "$HAS_FZF" == "true" ]]; then
  # Use fzf for multi-select. Strip ANSI from preview so fzf renders cleanly.
  FZF_INPUT="$(for i in "${!REPO_LINES[@]}"; do
    IFS=$'\t' read -r name _s _h vis lang stars updated desc <<<"${REPO_LINES[$i]}"
    printf '%d\t%s\t[%s | %s | ⭐%s | %s]  %s\n' \
      $((i+1)) "$name" "$vis" "$lang" "$stars" "$updated" "$desc"
  done)"

  info "fzf opens next — TAB to toggle, Enter to confirm, Esc to cancel."
  set +e
  FZF_OUT="$(printf '%s' "$FZF_INPUT" | fzf \
    --multi --ansi --with-nth=2.. --delimiter=$'\t' \
    --prompt="repos > " --height=80% --reverse --border \
    --header="TAB to toggle · Enter to confirm · Ctrl-A select all · Ctrl-D deselect all" \
    --bind 'ctrl-a:select-all,ctrl-d:deselect-all')"
  FZF_RC=$?
  set -e

  if (( FZF_RC != 0 )) || [[ -z "$FZF_OUT" ]]; then
    info "No selection made — nothing to clone."
    exit 0
  fi

  while IFS=$'\t' read -r idx _rest; do
    SELECTED_INDICES+=("$((idx-1))")
  done <<<"$FZF_OUT"
else
  # Numbered fallback selector. Supports indices/ranges/regex, repeatable.
  declare -A SELECTED_MAP=()

  print_list() {
    printf '\n'
    for i in "${!DISPLAY_LINES[@]}"; do
      local mark=" "
      [[ -n "${SELECTED_MAP[$i]:-}" ]] && mark="${GREEN}✓${RESET}"
      printf '  [%s] %s\n' "$mark" "${DISPLAY_LINES[$i]}"
    done
    printf '\n  %sSelected:%s %d / %d\n' "$BOLD" "$RESET" "${#SELECTED_MAP[@]}" "$REPO_COUNT"
  }

  apply_token() {
    local token="$1"
    case "$token" in
      all)
        for i in "${!REPO_LINES[@]}"; do SELECTED_MAP[$i]=1; done
        ;;
      none|clear)
        SELECTED_MAP=()
        ;;
      /*)
        local pat="${token#/}"
        local matched=0
        for i in "${!REPO_LINES[@]}"; do
          local name="${REPO_LINES[$i]%%$'\t'*}"
          if [[ "$name" =~ $pat ]]; then SELECTED_MAP[$i]=1; matched=$((matched+1)); fi
        done
        info "regex /${pat}/ matched ${matched} repo(s)"
        ;;
      *-*)
        local lo="${token%-*}" hi="${token#*-}"
        if [[ "$lo" =~ ^[0-9]+$ && "$hi" =~ ^[0-9]+$ ]]; then
          (( lo >= 1 && hi >= lo && hi <= REPO_COUNT )) \
            || { warn "range out of bounds: $token"; return; }
          for ((j=lo; j<=hi; j++)); do SELECTED_MAP[$((j-1))]=1; done
        else
          warn "ignored token: $token"
        fi
        ;;
      *)
        if [[ "$token" =~ ^[0-9]+$ ]]; then
          (( token >= 1 && token <= REPO_COUNT )) \
            || { warn "index out of bounds: $token"; return; }
          SELECTED_MAP[$((token-1))]=1
        else
          warn "ignored token: $token"
        fi
        ;;
    esac
  }

  print_list
  printf '\n  %sEnter selection (Enter on empty line to confirm). See --help for syntax.%s\n' "$DIM" "$RESET"
  while :; do
    read -r -p "  > " line || break
    [[ -z "$line" ]] && break
    # Split on whitespace and commas.
    IFS=', ' read -r -a tokens <<<"$line"
    for tok in "${tokens[@]}"; do
      [[ -n "$tok" ]] && apply_token "$tok"
    done
    print_list
  done

  if (( ${#SELECTED_MAP[@]} == 0 )); then
    info "No repositories selected — nothing to clone."
    exit 0
  fi

  for i in "${!REPO_LINES[@]}"; do
    [[ -n "${SELECTED_MAP[$i]:-}" ]] && SELECTED_INDICES+=("$i")
  done
fi

# ─── 6. destination + clone ───────────────────────────────────────────────────
step 6 "Cloning ${#SELECTED_INDICES[@]} repositor$( ((${#SELECTED_INDICES[@]}==1)) && echo y || echo ies )"

# Resolve destination dir.
if [[ -z "$DEST_DIR" ]]; then
  default_dest="$HOME"
  read -r -p "  Destination directory [${default_dest}]: " entered || true
  DEST_DIR="${entered:-$default_dest}"
fi
# Expand ~ and resolve relative paths.
DEST_DIR="${DEST_DIR/#\~/$HOME}"
[[ "$DEST_DIR" = /* ]] || DEST_DIR="$PWD/$DEST_DIR"

if [[ ! -d "$DEST_DIR" ]]; then
  warn "Destination '$DEST_DIR' does not exist."
  if [[ "$ASSUME_YES" == "true" ]]; then
    mkdir -p "$DEST_DIR"
  else
    read -r -p "  Create it? [Y/n] " ans
    case "${ans,,}" in
      n|no) die "Aborted — no destination directory." ;;
      *)    mkdir -p "$DEST_DIR" || die "Could not create $DEST_DIR" ;;
    esac
  fi
fi
ok "Destination: ${BOLD}${DEST_DIR}${RESET}"

# Build the work list (skip already-present clones).
PLAN_FILE="$(mktemp)"
SKIP_FILE="$(mktemp)"
trap 'rm -f "$PLAN_FILE" "$SKIP_FILE"' EXIT

for i in "${SELECTED_INDICES[@]}"; do
  IFS=$'\t' read -r name ssh_url https_url _rest <<<"${REPO_LINES[$i]}"
  repo_basename="${name##*/}"
  target="$DEST_DIR/$repo_basename"
  if [[ -e "$target" ]]; then
    printf '%s\t%s\n' "$name" "$target" >> "$SKIP_FILE"
    continue
  fi
  if [[ "$PROTOCOL" == "ssh" ]]; then
    printf '%s\t%s\t%s\n' "$name" "$ssh_url" "$target" >> "$PLAN_FILE"
  else
    printf '%s\t%s\t%s\n' "$name" "$https_url" "$target" >> "$PLAN_FILE"
  fi
done

SKIP_COUNT=$(wc -l < "$SKIP_FILE" | tr -d ' ')
PLAN_COUNT=$(wc -l < "$PLAN_FILE" | tr -d ' ')

if (( SKIP_COUNT > 0 )); then
  warn "Skipping ${SKIP_COUNT} already-present path(s):"
  while IFS=$'\t' read -r name target; do
    printf '      %s%s%s → %s\n' "$DIM" "$name" "$RESET" "$target"
  done < "$SKIP_FILE"
fi

if (( PLAN_COUNT == 0 )); then
  info "Nothing new to clone."
  exit 0
fi

printf '\n  %sWill clone %d repo(s) via %s into %s:%s\n' "$BOLD" "$PLAN_COUNT" "$PROTOCOL" "$DEST_DIR" "$RESET"
while IFS=$'\t' read -r name url target; do
  printf '      %s%s%s  ← %s\n' "$BLUE" "$name" "$RESET" "$url"
done < "$PLAN_FILE"

if [[ "$ASSUME_YES" != "true" ]]; then
  read -r -p $'\n  Proceed? [Y/n] ' ans
  case "${ans,,}" in
    n|no) die "Aborted." ;;
  esac
fi

# Clone in parallel with xargs. Each worker prints its own status.
export PROTOCOL
clone_one() {
  local name="$1" url="$2" target="$3"
  if git clone --quiet "$url" "$target" 2>/tmp/.clone-err.$$; then
    printf '  %s✓%s %s\n' $'\e[1;32m' $'\e[0m' "$name"
    rm -f /tmp/.clone-err.$$
  else
    printf '  %s✗%s %s — %s\n' $'\e[1;31m' $'\e[0m' "$name" "$(cat /tmp/.clone-err.$$ 2>/dev/null | head -n1)"
    rm -f /tmp/.clone-err.$$
    return 1
  fi
}
export -f clone_one

FAIL_FILE="$(mktemp)"
trap 'rm -f "$PLAN_FILE" "$SKIP_FILE" "$FAIL_FILE"' EXIT

printf '\n'
# xargs -P parallel; -n3 so each invocation gets one row's 3 fields.
# Use NUL-delimited records to be safe with weird names (unlikely here, but cheap).
while IFS=$'\t' read -r name url target; do
  printf '%s\0%s\0%s\0' "$name" "$url" "$target"
done < "$PLAN_FILE" \
| xargs -0 -n3 -P "$PARALLEL" bash -c 'clone_one "$@" || echo "$1" >> '"$FAIL_FILE"'' _ \
|| true

FAIL_COUNT=$(wc -l < "$FAIL_FILE" | tr -d ' ')
SUCCESS_COUNT=$((PLAN_COUNT - FAIL_COUNT))

printf '\n%s╭─────────────────────────────────────────────╮%s\n' "$GREEN" "$RESET"
printf '%s│              clone run complete             │%s\n' "$GREEN" "$RESET"
printf '%s╰─────────────────────────────────────────────╯%s\n\n' "$GREEN" "$RESET"

printf '  Destination    : %s\n' "$DEST_DIR"
printf '  Protocol       : %s\n' "$PROTOCOL"
printf '  Cloned         : %s%d%s\n' "$GREEN" "$SUCCESS_COUNT" "$RESET"
(( SKIP_COUNT > 0 )) && printf '  Skipped        : %s%d%s (already present)\n' "$YELLOW" "$SKIP_COUNT" "$RESET"
(( FAIL_COUNT > 0 )) && {
  printf '  Failed         : %s%d%s\n' "$RED" "$FAIL_COUNT" "$RESET"
  printf '    %s\n' "$(tr '\n' ' ' < "$FAIL_FILE")"
}
printf '\n'

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
