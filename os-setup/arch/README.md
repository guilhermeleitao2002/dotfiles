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

## ⌨ Keybinds

The modifier is **Super** (the Windows key). All binds live in
[`hyprland.conf`](hyprland/.config/hypr/hyprland.conf) — `bind = …` for normal
shortcuts, `bindm = …` for mouse drags, `bindel = …` for held-down media keys,
and `bindl = …` for media keys that should still fire when locked.

> Note: Hyprland is a tiling WM, so there are no "tabs" at the window-manager
> level. Each instance of an app is its own tiled window, and new ones are
> launched via the app-launcher (`Super` + `R`) or a direct keybind below.

### Launching apps

| Shortcut | Action |
| --- | --- |
| `Super` + `T` | Open a new terminal window (`kitty`) |
| `Super` + `R` | Open the app launcher (`wofi --show drun`) — type to launch anything |
| `Super` + `E` | Open the file manager (`nautilus`) |
| `Print` | Region screenshot, frozen, copied to clipboard (`hyprshot`) |
| `Ctrl` + `Print` | Whole-window screenshot, frozen (`hyprshot`) |
| `Super` + `L` | Lock screen (`hyprlock`) and suspend |

### Window management

| Shortcut | Action |
| --- | --- |
| `Super` + `Q` | Close the active window |
| `Super` + `V` | Toggle floating mode for the active window |
| `Super` + `P` | Toggle pseudotile (floating-sized window while tiled) |
| `Super` + `J` | Toggle dwindle split direction (vertical ↔ horizontal) |
| `Super` + `M` | Exit Hyprland (log out of the session) |
| `Super` + drag left-click | Move the window |
| `Super` + drag right-click | Resize the window |

### Focus

| Shortcut | Action |
| --- | --- |
| `Super` + `A` / `D` | Focus window to the left / right |
| `Super` + `W` / `S` | Focus window above / below |

### Workspaces

| Shortcut | Action |
| --- | --- |
| `Super` + `1` … `0` | Switch to workspace 1–10 |
| `Super` + `Shift` + `1` … `0` | Move active window to workspace 1–10 |
| `Super` + scroll wheel | Cycle through existing workspaces |
| `Super` + `Z` | Toggle the special workspace (scratchpad) |
| `Super` + `Shift` + `Z` | Move active window to the special workspace |

Selected apps autoland on specific workspaces:

| App | Workspace |
| --- | --- |
| `kitty` (terminal) | 1 |
| `firefox` | 2 |
| `discord` | 3 |

### Media & brightness keys

Wired through `wpctl` (from `wireplumber`), `brightnessctl`, and `playerctl`:

| Key | Action |
| --- | --- |
| `XF86AudioRaiseVolume` / `Lower` | Volume up / down (5%) |
| `XF86AudioMute` | Toggle output mute |
| `XF86AudioMicMute` | Toggle mic mute |
| `XF86MonBrightnessUp` / `Down` | Brightness up / down (5%) |
| `XF86AudioPlay` / `Pause` | Play / pause |
| `XF86AudioNext` / `Prev` | Next / previous track |

## 🖐 Touchpad gestures

Since Hyprland 0.55, the legacy `gestures { workspace_swipe = true }` hyprlang
options were removed in favor of a new lua-only gesture system. The bundled
[`hyprland.conf`](hyprland/.config/hypr/hyprland.conf) keeps the tuning options
(like `workspace_swipe_distance`) but no longer enables the swipe itself — the
master switch and finger-count options now live only in lua.

To re-enable a 2-finger horizontal workspace swipe, create
`~/.config/hypr/hyprland.lua` and add:

```lua
hl.gesture({ fingers = 2, direction = "horizontal", action = "workspace" })
```

Other supported actions include `move`, `resize`, `close`, `fullscreen`,
`float`, `special` (toggle a special workspace), and `cursor_zoom`. See the
[Hyprland Gestures wiki](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/)
for the full list of fields (`fingers`, `direction`, `action`, `mods`, `scale`)
and worked examples.

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
