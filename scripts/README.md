# 🧰 Utility scripts

Standalone, cross-distro helpers that don't belong to any particular OS
bootstrap. Each script is self-contained, idempotent, and safe to re-run.

> ⬆️ For the repository overview, see the [root README](../README.md).

---

## 🔗 Calling them from anywhere

Both bundled `.zshrc` files in [../os-setup/](../os-setup/README.md) add this
directory to your `PATH`:

```bash
export PATH="$HOME/dotfiles/scripts:$PATH"
```

After running one of the OS bootstraps (or sourcing the matching `.zshrc`),
every script in this directory is callable by its filename from any working
directory — for example, `clone-github-repos.sh` or `setup-github-ssh.sh`.

If you'd rather not modify your shell config, you can also invoke them
directly:

```bash
~/dotfiles/scripts/setup-github-ssh.sh
~/dotfiles/scripts/clone-github-repos.sh
```

---

## 📜 Available scripts

### `setup-github-ssh.sh`

Generates an SSH key on the current machine and registers it with GitHub via
the `gh` CLI.

```bash
setup-github-ssh.sh [options]
```

Highlights:

- Defaults to an `ed25519` key at `~/.ssh/id_ed25519` (override with `--type` / `--file`).
- Uses your existing `git config user.email` for the key comment when available.
- Loads the key into a running `ssh-agent` (starts one if needed).
- Skips the GitHub upload if a key with the same public material is already on your account.
- Optional `--signing-key` flag also registers the key as a GitHub SSH commit-signing key.
- Verifies the result with `ssh -T git@github.com` unless `--skip-verify` is given.

Run `setup-github-ssh.sh --help` for the full flag list.

### `clone-github-repos.sh`

Lists the GitHub repositories you have access to and clones the ones you pick
into a directory of your choice.

```bash
clone-github-repos.sh [options]
```

Highlights:

- Multi-select interface — uses [`fzf`](https://github.com/junegunn/fzf) when available, falls back to a numbered picker with `all` / `none` / `1,3,5-8` / `/regex` syntax.
- Auto-detects whether SSH or HTTPS works, and offers to run `setup-github-ssh.sh` if SSH isn't set up yet.
- Filters: `--owner <login>`, `--include-forks`, `--include-archived`, `--no-private`, `--limit <n>`.
- Parallel cloning with `--parallel <n>` (default 4).
- Skips repos that already exist on disk.
- Auto-installs missing tools (`git`, `gh`, `jq`, `ssh`, `fzf`) on pacman / apt / dnf / zypper / brew systems unless `--no-install` is set.

Run `clone-github-repos.sh --help` for the full flag list and selection
syntax.

---

## 📂 Directory layout

```
scripts/
├── README.md                 # this file
├── clone-github-repos.sh     # interactive bulk-clone of your GitHub repos
└── setup-github-ssh.sh       # generate an SSH key and register it with GitHub
```
