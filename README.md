# 🛠 Dotfiles Setup

This repository automates the installation and configuration of two environments:

* **Arch Linux desktop** with [Hyprland](https://github.com/hyprwm/Hyprland), Catppuccin theming, kitty, waybar, wofi, hyprlock, and zsh — see [🖥 Arch Linux Setup](#-arch-linux-setup).
* **Ubuntu / WSL shell** with zsh, Oh My Zsh, autosuggestions, syntax highlighting, fastfetch, and the bundled `.zshrc` — see [🐧 Ubuntu / WSL Setup](#-ubuntu--wsl-setup).

Pick the section that matches the box you're on.

---

## 🐧 Ubuntu / WSL Setup

One command on a fresh Ubuntu install:

```bash
git clone https://github.com/<you>/dotfiles ~/dotfiles
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

## 📋 Setup Overview

The script `setup.sh` performs the following tasks:

* Installs required packages (via `yay`)
* Stows and applies personal configurations using GNU `stow`
* Sets up wallpaper, terminal, GTK themes, status bar, application launcher, lockscreen, and Hyprland configuration
* Applies visual theming using [Catppuccin](https://github.com/catppuccin)

---

## 🧰 Requirements

Make sure you have the following tools and prerequisites installed:

* [yay](https://github.com/Jguer/yay): AUR helper for package management
* [stow](https://www.gnu.org/software/stow/): For managing dotfiles via symlinks
* A Hyprland-compatible Wayland environment
* A working internet connection

---

## 📂 Directory Structure

Your dotfiles repository should include the following folders:

```
.
├── backgrounds/
├── hyprlock/
├── hyprmocha/
├── hyprpaper/
├── kitty/
├── waybar/
├── wofi/
├── .zshrc
├── zsh_setup.sh
├── setup.sh
└── hyprland.conf
```

---

## 🚀 What the Script Does

### 1. **Stow & Install Base Tools**

```bash
yay -Sy stow
```

Installs GNU `stow` to manage symlinks of your configuration files.

### 2. **Wallpaper Setup**

```bash
yay -Sy hyprpaper
stow hyprpaper
stow backgrounds
```

Installs `hyprpaper` and applies wallpaper-related configuration using `stow`.

### 3. **Kitty Terminal Configuration**

```bash
stow kitty
./zsh_setup.sh
```

Applies terminal settings and runs a separate ZSH setup script.

### 4. **Waybar Status Bar Configuration**

```bash
killall waybar
rm ~/.config/waybar/*
stow waybar
```

Kills any running Waybar instances, clears old configs, and applies your custom config.

### 5. **GTK Application Theming**

```bash
yay -Sy nwg-look
yay -Sy catppuccin-gtk-theme-mocha
nwg-look
```

Installs a GTK theme selector and Catppuccin Mocha GTK theme. Launches `nwg-look` for manual theme selection.

### 6. **Wofi App Launcher Setup**

```bash
stow wofi
```

Applies configuration for Wofi, a Wayland-native application launcher.

### 7. **Hyprlock Lockscreen Setup**

```bash
sudo rm -rf ~/.config/hypr/hyprlock.conf
stow hyprlock
stow hyprmocha
```

Removes old Hyprlock config, applies new settings and Catppuccin-inspired themes.

### 8. **Hyprland Configuration**

```bash
sudo rm ~/.config/hypr/hyprland.conf
cp hyprland.conf ~/.config/hypr/
```

Applies the main Hyprland configuration file directly.

### 9. **Reboot**

```bash
reboot
```

Reboots the system to apply all changes.

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
