# 🖥 Arch Linux Setup

A fresh Arch (or Arch-based) install becomes a fully themed Hyprland desktop
with one command. The script is idempotent and only prompts for your sudo
password once at the start — and optionally at the end for the GTK theme
picker and reboot.

> ⬆️ For the OS-setup overview, see [../README.md](../README.md).
> ⬆️ For the repository overview, see the [root README](../../README.md).

---

## 🚀 Install

```bash
git clone https://github.com/guilhermeleitao2002/dotfiles ~/dotfiles
~/dotfiles/os-setup/arch/setup.sh
```

## 📋 What it does

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

## 🧩 Flags

```bash
./setup.sh --help
```

The most common ones:

| Flag | Effect |
| --- | --- |
| `-f, --filesystems "<a,b,c>"` | Override the default WSL/LVM `df -h` patterns in the bundled `.zshrc` (see [disk-info personalization](#-personalizing-the-disk-info-block)). |
| `--no-disk-info` | Strip the `df -h` lines from `.zshrc` entirely. |
| `--skip-theme-gui` | Don't launch the interactive `nwg-look` GTK picker. |
| `--no-reboot` | Don't prompt to reboot at the end. |

## 🧩 Personalizing the disk-info block

The bundled `.zshrc` prints a `df -h` summary at every shell startup, filtered
by device path. By default the patterns are `/dev/mapper/volgroup0-lv_root` and
`/dev/mapper/volgroup0-lv_home`, which match the author's WSL/LVM setup.

If your box uses different device paths, pass them in with `--filesystems`:

```bash
./setup.sh --filesystems "/dev/nvme0n1p2,/dev/sda1"
```

Each comma-separated value becomes its own colored `df -h | grep` line, in
order, right after the header row. To skip the disk-info block entirely:

```bash
./setup.sh --no-disk-info
```

## 📂 Directory layout

```
arch/
├── README.md             # this file
├── setup.sh              # the bootstrap script
├── .zshrc                # copied to ~/.zshrc (with backup)
├── backgrounds/          # stow: ~/.config/backgrounds/
├── hyprland/             # stow: ~/.config/hypr/hyprland.conf
├── hyprlock/             # stow: ~/.config/hypr/hyprlock.conf
├── hyprmocha/            # stow: ~/.config/hypr/mocha.conf
├── hyprpaper/            # stow: ~/.config/hypr/hyprpaper.conf
├── kitty/                # stow: ~/.config/kitty/
├── waybar/               # stow: ~/.config/waybar/
└── wofi/                 # stow: ~/.config/wofi/
```

Every Hyprland-related config is a proper stow package, so editing the symlink
at `~/.config/hypr/hyprland.conf` edits the file in the repo directly — no
more drift between your live config and your dotfiles.
