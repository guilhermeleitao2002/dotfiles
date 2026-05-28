# 🐧 Ubuntu / WSL Setup

A minimal, headless-friendly bootstrap that turns a fresh Ubuntu install
(including WSL) into a comfortable zsh shell with Oh My Zsh, autosuggestions,
syntax highlighting, and fastfetch.

> ⬆️ For the OS-setup overview, see [../README.md](../README.md).
> ⬆️ For the repository overview, see the [root README](../../README.md).

---

## 🚀 Install

One command on a fresh Ubuntu install:

```bash
git clone https://github.com/guilhermeleitao2002/dotfiles ~/dotfiles
~/dotfiles/os-setup/ubuntu/setup.sh
```

The script (`setup.sh`) is **idempotent** and **non-interactive** beyond the
initial sudo prompt.

## 📋 What it does

1. Caches your sudo credentials and keeps them alive for the rest of the run.
2. Runs `apt update && apt upgrade && apt autoremove`.
3. Installs base packages: `zsh git curl wget ca-certificates`.
4. Installs `fastfetch` from apt, falling back to the official PPA on Ubuntu 22.04 and older.
5. Installs [Oh My Zsh](https://ohmyz.sh/) in `--unattended` mode (no shell hijack, no `.zshrc` clobber).
6. Clones (or pulls, if already present) the [`zsh-autosuggestions`](https://github.com/zsh-users/zsh-autosuggestions) and [`zsh-syntax-highlighting`](https://github.com/zsh-users/zsh-syntax-highlighting) plugins.
7. Backs up your existing `~/.zshrc` with a timestamped suffix (only if it differs) and installs the one shipped in this repo.
8. Adds `zsh` to `/etc/shells` if missing and sets it as your default login shell via `sudo chsh`.
9. `exec`s into zsh so you land in the new shell immediately — no logout needed.

## 🧩 Flags

```bash
./setup.sh --help
```

| Flag | Effect |
| --- | --- |
| `-f, --filesystems "<a,b,c>"` | Replace the default WSL/LVM device paths in `~/.zshrc` with this comma-separated list of grep patterns. |
| `--no-disk-info` | Strip the `df -h` disk-info lines from `.zshrc` entirely. |

## 🧩 Personalizing the disk-info block

The bundled `.zshrc` prints a `df -h` summary at every shell startup, filtered
by device path. By default the patterns are `/dev/mapper/volgroup0-lv_root` and
`/dev/mapper/volgroup0-lv_home`, matching the author's WSL/LVM setup. These
defaults are kept when the script is run with no flags, so existing WSL users
get the same shell they always had.

If your box uses different device paths, pass them in with `--filesystems`:

```bash
./setup.sh --filesystems "/dev/sda1,/dev/sda2"
```

Each comma-separated value becomes its own colored `df -h | grep` line, in
order, right after the header row. To skip the disk-info block entirely:

```bash
./setup.sh --no-disk-info
```

## 📂 Directory layout

```
ubuntu/
├── README.md   # this file
├── setup.sh    # the bootstrap script
└── .zshrc      # copied to ~/.zshrc (with backup)
```
