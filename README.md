# 🛠 gleitao · dotfiles & scripts

A personal collection of system bootstraps, configuration files, and utility
scripts. What started as an Arch + Ubuntu dotfiles repo has grown into a
general-purpose toolbox — feel free to cherry-pick whatever is useful.

---

## 📂 Repository layout

```
dotfiles/
├── os-setup/   # Idempotent OS bootstraps + their configs (Arch, Ubuntu)
│               # See os-setup/README.md
└── scripts/    # Standalone utility scripts (GitHub SSH setup, repo cloner, …)
                # See scripts/README.md
```

Each subdirectory has its own README that goes into more detail.

| Directory                                  | What lives there                                                                                       |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| [os-setup/](./os-setup/README.md)          | One-command bootstrap scripts and dotfiles for fresh installs. Currently covers Arch Linux and Ubuntu. |
| [os-setup/arch/](./os-setup/arch/README.md)     | Hyprland desktop · Catppuccin theming · kitty · waybar · wofi · hyprlock · zsh.                       |
| [os-setup/ubuntu/](./os-setup/ubuntu/README.md) | Headless / WSL zsh shell with Oh My Zsh, autosuggestions, syntax highlighting, fastfetch.             |
| [scripts/](./scripts/README.md)            | Cross-distro helpers — register an SSH key with GitHub, bulk-clone your GitHub repos, …               |

---

## 🚀 Getting started

Clone the repository to your home directory:

```bash
git clone https://github.com/guilhermeleitao2002/dotfiles ~/dotfiles
```

Then jump into whichever piece you need:

- **Bootstrap a machine →** see [os-setup/](./os-setup/README.md) and pick your OS.
- **Use the utility scripts →** see [scripts/](./scripts/README.md). Either of the
  OS setups above adds `~/dotfiles/scripts` to your `PATH`, so once your shell
  is configured you can invoke any script by name from anywhere.

---

## 🧑 Author

Created by [Guilherme Leitão](https://github.com/guilhermeleitao2002).
Feel free to fork and customize for your own environment!

---

## 📄 License

MIT License. See [LICENSE](./LICENSE) for details.
