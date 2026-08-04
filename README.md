# dotfiles
My config files for setting up my system

## Migrating from armarquez/dotfiles

This repo replaces `armarquez/dotfiles`, which is now private. `dotfiles-v2` starts from a single
fresh commit — there's no shared history with the old repo, so a normal `git pull` after switching
remotes won't work; local history has to be reset to match.

If a machine already has `armarquez/dotfiles` cloned, pull the latest changes there first (it still
has the `migrate-to-v2` recipe), then run:

```bash
just migrate-to-v2
```

That repoints `origin` at this repo and hard-resets local `main` to match. Equivalent by hand:

```bash
git remote set-url origin git@github.com:armarquez/dotfiles-v2.git
git fetch origin
git checkout main
git reset --hard origin/main
```

For a brand-new machine, just clone this repo directly — no migration needed.

## Packages to Install

- zsh
- stow
- golang
- direnv
- pygitup
- tig
- just (command runner)

## Using Just

This repo includes a `justfile` for common tasks. Run `just` to see available commands:

```bash
just              # Show available commands
just init         # Run one-time setup
just stow         # Symlink dotfiles
just update-zsh   # Update zsh-quickstart-kit subtree
just update-plugins  # Update zgenom plugins
just regen        # Regenerate zgenom init.zsh
```

## Configuration Structure

This repo uses fragment files in `~/.zshrc.d/` for configuration. Files are loaded in alphanumeric order:

| File | Description |
|------|-------------|
| `50-base.zsh` | Base config (pyenv, golang, nvm, etc.) - loaded everywhere |
| `50-base-aliases.zsh` | Base aliases - loaded everywhere |
| `50-base-functions.zsh` | Base functions - loaded everywhere |
| `80-airbnb.zsh` | Airbnb config - **auto-detects environment** |
| `80-airbnb-aliases.zsh` | Airbnb aliases - **auto-detects environment** |
| `80-airbnb-functions.zsh` | Airbnb functions - **auto-detects environment** |

The work-specific files automatically detect the environment and only load when appropriate. This means you can use the same `main` branch on both personal and work machines - no branch switching needed!

## zsh

This is a git subtree of [zsh-quickstart-kit](https://github.com/unixorn/zsh-quickstart-kit). To update, follow the git subtree update strategy [outlined by Atlassian blog](https://www.atlassian.com/git/tutorials/git-subtree):

Adding the subtree as a remote allows us to refer to it in shorter form:

```bash
git remote add -f zsh-quickstart-kit git@github.com:unixorn/zsh-quickstart-kit.git
```

(This is only done initially) Now we can add the subtree (as before), but now we can refer to the remote in short form:

```bash
git subtree add --prefix zsh zsh-quickstart-kit main --squash
```

The command to update the sub-project at a later date becomes:

```bash
git fetch zsh-quickstart-kit main
git subtree pull --prefix zsh zsh-quickstart-kit main --squash
```

### Adding zsh completions

Here is how you can add new zsh completions, like adding Google Cloud SDK completions as indicated in `brew` caveats

```bash
mkdir -p ~/.zsh-completions
ln -s /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc ~/.zsh-completions/path.zsh.inc
ln -s /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc ~/.zsh-completions/completion.zsh.inc
```

## Cloud dev workspaces (bare clone layout)

Some cloud dev environments clone this repo bare to `$HOME/.dotfiles` (work-tree `$HOME`), then
run `.init.sh` once on a brand-new workspace and `.startup.sh` on every start/resume. `.startup.sh`
self-heals: if `~/.zshrc` isn't a symlink or `~/.claude/settings.json` is missing, it re-runs
`.init.sh`.

### Known issue: unattended clone can fail for personal-namespace repos

Some of these platforms run the bootstrap clone before any personal SSH agent is forwarded, so
`git clone --bare` against a personal-namespace repo can fail with an SSH certificate scoping
error tied to the platform's own credential policy. The workspace comes up degraded and dotfiles
are never cloned. This is a platform-level issue, not something fixable from this repo — report it
to whoever owns the platform.

**Recovery** — inside a live interactive session on the workspace (where your personal SSH agent
is forwarded):

```bash
rm -rf ~/.dotfiles
git clone --bare <your-dotfiles-remote-url> ~/.dotfiles
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" config status.showUntrackedFiles no
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" reset --hard main
~/.init.sh
```

If the clone already exists but is stale or diverged, `just repair-bare-clone` does the fetch +
reset + re-init in one step (run from `$HOME`, since that's where the stowed `justfile` lives).
