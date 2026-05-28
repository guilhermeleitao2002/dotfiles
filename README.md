# 🛠 Dotfiles Setup

This repository automates the installation and configuration of two environments:

* **Arch Linux desktop** with [Hyprland](https://github.com/hyprwm/Hyprland), Catppuccin theming, kitty, waybar, wofi, hyprlock, and zsh — see [🖥 Arch Linux Setup](#-arch-linux-setup).
* **Ubuntu / WSL shell** with zsh, Oh My Zsh, autosuggestions, syntax highlighting, fastfetch, and the bundled `.zshrc` — see [🐧 Ubuntu / WSL Setup](#-ubuntu--wsl-setup).

Pick the section that matches the box you're on.

---

## 🐧 Ubuntu / WSL Setup

One command on a fresh Ubuntu install:

```bash
git clone https://github.com/guilhermeleitao2002/dotfiles ~/dotfiles
~/dotfiles/ubuntu/setup.sh
```

The script (`ubuntu/setup.sh`) is **idempotent** and **non-interactive** beyond the initial sudo prompt. It does the following:

1. Caches your sudo credentials and keeps them alive for the rest of the run.
2. Runs `apt update && apt upgrade && apt autoremove`.
3. Installs base packages: `zsh git curl wget ca-certificates`.
4. Installs `fastfetch` from apt, falling back to the official PPA on Ubuntu 22.04 and older.
5. Installs [Oh My Zsh](https://ohmyz.sh/) in `--unattended` mode (no shell hijack, no `.zshrc` clobber).
6. Clones (or pulls, if already present) the [`zsh-autosuggestions`](https://github.com/zsh-users/zsh-autosuggestions) and [`zsh-syntax-highlighting`](https://github.com/zsh-users/zsh-syntax-highlighting) plugins.
7. Backs up your existing `~/.zshrc` with a timestamped suffix (only if it differs) and installs the one shipped in this repo.
8. Adds `zsh` to `/etc/shells` if missing and sets it as your default login shell via `sudo chsh`.
9. `exec`s into zsh so you land in the new shell immediately — no logout needed.

### 🧩 Personalizing the disk-info block

The bundled `.zshrc` prints a `df -h` summary at every shell startup, filtered by device path. By default the patterns are `/dev/mapper/volgroup0-lv_root` and `/dev/mapper/volgroup0-lv_home`, which match the author's WSL/LVM setup. These defaults are kept when the script is run with no flags, so existing WSL users get the same shell they always had.

If your box uses different device paths, pass them in with `--filesystems`:

```bash
~/dotfiles/ubuntu/setup.sh --filesystems "/dev/sda1,/dev/sda2"
```

Each comma-separated value becomes its own colored `df -h | grep` line, in order, right after the header row. To skip the disk-info block entirely:

```bash
~/dotfiles/ubuntu/setup.sh --no-disk-info
```

Run `setup.sh --help` for the full flag list.

---

## 🖥 Arch Linux Setup

One command on a fresh Arch install:

```bash
git clone https://github.com/<you>/dotfiles ~/dotfiles
~/dotfiles/arch/setup.sh
```

The script (`arch/setup.sh`) is **idempotent**. It only prompts for your sudo password once at the start, and (optionally) at the end for the GTK theme picker and reboot.

### 📋 What it does

1. Runs a full `pacman -Syu` (no partial-upgrade footguns).
2. Installs base packages from the official repos: `git base-devel stow zsh fastfetch curl wget`.
3. Bootstraps `yay` from the AUR if it isn't already installed.
4. Installs the full Hyprland desktop ecosystem and theming:
   * **Window manager / wallpaper / lockscreen** — `hyprland`, `hyprpaper`, `hyprlock`
   * **Status bar / launcher / terminal** — `waybar`, `wofi`, `kitty`
   * **GTK theming** — `nwg-look`, `catppuccin-gtk-theme-mocha` (AUR)
   * **Fonts** — `ttf-jetbrains-mono-nerd`, `noto-fonts`, `noto-fonts-emoji`
5. Installs [Oh My Zsh](https://ohmyz.sh/) unattended, plus [`zsh-autosuggestions`](https://github.com/zsh-users/zsh-autosuggestions) and [`zsh-syntax-highlighting`](https://github.com/zsh-users/zsh-syntax-highlighting).
6. Stows every dotfile package into `$HOME` via GNU `stow`. Conflicting real files are moved to `<file>.backup.<timestamp>` first, so existing configs are preserved.
7. Adds `zsh` to `/etc/shells` if missing and sets it as your default login shell.
8. Optionally launches `nwg-look` for the GTK theme picker, then optionally reboots — both prompt, both can be skipped with flags.

### 🧩 Flags

```bash
arch/setup.sh --help
```

The most common ones:

| Flag | Effect |
| --- | --- |
| `-f, --filesystems "<a,b,c>"` | Override the default WSL/LVM `df -h` patterns in the bundled `.zshrc` (see [Ubuntu section](#-personalizing-the-disk-info-block) — same semantics). |
| `--no-disk-info` | Strip the `df -h` lines from `.zshrc` entirely. |
| `--skip-theme-gui` | Don't launch the interactive `nwg-look` GTK picker. |
| `--no-reboot` | Don't prompt to reboot at the end. |

### 📂 Directory Structure

The repo layout under `arch/`:

```
arch/
├── setup.sh             # the bootstrap script
├── .zshrc               # copied to ~/.zshrc (with backup)
├── backgrounds/         # stow: ~/.config/backgrounds/
├── hyprland/            # stow: ~/.config/hypr/hyprland.conf
├── hyprlock/            # stow: ~/.config/hypr/hyprlock.conf
├── hyprmocha/           # stow: ~/.config/hypr/mocha.conf
├── hyprpaper/           # stow: ~/.config/hypr/hyprpaper.conf
├── kitty/               # stow: ~/.config/kitty/
├── waybar/              # stow: ~/.config/waybar/
└── wofi/                # stow: ~/.config/wofi/
```

Every Hyprland-related config is now a proper stow package, so editing the symlink at `~/.config/hypr/hyprland.conf` edits the file in the repo directly — no more drift between your live config and your dotfiles.

---

## 🖼 Screenshot

This is what it looks like:

![Hypr Setup](setup.png)

---

## 🧑 Author

Created by [Guilherme Leitão](https://github.com/your-username)
Feel free to fork and customize for your own environment!

---

## 📄 License

MIT License.
See [LICENSE](./LICENSE) for more details.
