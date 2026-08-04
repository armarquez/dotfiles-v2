# Dotfiles management justfile

# Claude Code config recipes (see claude/justfile); zsh recipes stay here to avoid subtree clobber
mod claude

# Default recipe - show available commands
default:
    @just --list

# Run the init script (one-time setup)
init:
    ./.init.sh

# Run the startup script
startup:
    ./.startup.sh

# Back up any real (non-symlink) files under $HOME that the zsh package would overwrite
# (e.g. a base-image ~/.zshrc) — mirrors the same pattern in claude/justfile's stow recipe.
# Pre-creates .zshrc.d as a real directory first, so stow always links its fragments
# individually instead of symlinking the whole directory — walking a symlinked directory's
# contents would resolve straight back to the source files themselves, and "backing up" a
# conflict there would actually rename the repo's own tracked files.
_backup-zsh-conflicts:
    #!/usr/bin/env bash
    set -euo pipefail
    STOW_DIR="{{ justfile_directory() }}/zsh/zsh"
    TARGET="{{ home_directory() }}"
    mkdir -p "$TARGET/.zshrc.d"
    # find, not a bare glob, so dotfiles (.zshrc, .zshrc.d, ...) are included.
    while IFS= read -r -d '' entry; do
        name="$(basename "$entry")"
        target="$TARGET/$name"
        [[ -L "$target" ]] && continue
        if [[ -d "$entry" ]]; then
            while IFS= read -r -d '' sub; do
                subtarget="$target/$(basename "$sub")"
                if [[ -f "$subtarget" && ! -L "$subtarget" ]]; then
                    echo "==> Backing up $subtarget -> ${subtarget}.pre-dotfiles.bak"
                    mv "$subtarget" "${subtarget}.pre-dotfiles.bak"
                fi
            done < <(find "$entry" -mindepth 1 -maxdepth 1 -type f -print0)
        elif [[ -f "$target" ]]; then
            echo "==> Backing up $target -> ${target}.pre-dotfiles.bak"
            mv "$target" "${target}.pre-dotfiles.bak"
        fi
    done < <(find "$STOW_DIR" -mindepth 1 -maxdepth 1 -print0)

# Symlink dotfiles using stow (backs up existing non-symlink files first)
stow: _backup-zsh-conflicts
    cd zsh && stow --target="$HOME" zsh

# Remove symlinks created by stow
unstow:
    cd zsh && stow --delete --target="$HOME" zsh

# Re-stow (useful after adding new files) — backs up conflicts first, same as stow
restow: _backup-zsh-conflicts
    cd zsh && stow --restow --target="$HOME" zsh

# Add zsh-quickstart-kit as a remote (safe to run multiple times)
setup-zsh-remote:
    #!/usr/bin/env bash
    if git remote get-url zsh-quickstart-kit &>/dev/null; then
        echo "Remote 'zsh-quickstart-kit' already exists"
        git remote get-url zsh-quickstart-kit
    else
        git remote add zsh-quickstart-kit git@github.com:unixorn/zsh-quickstart-kit.git
        echo "Added remote 'zsh-quickstart-kit'"
    fi

# Fetch zsh-quickstart-kit without merging (safe, just updates remote refs)
fetch-zsh:
    git fetch zsh-quickstart-kit main

# Update zsh-quickstart-kit subtree from upstream (may require conflict resolution)
update-zsh: setup-zsh-remote fetch-zsh
    @echo "Pulling zsh-quickstart-kit subtree. If conflicts occur, resolve them and run 'git commit'"
    git subtree pull --prefix zsh zsh-quickstart-kit main --squash

# Update zgenom plugins
update-plugins:
    zsh -c 'source ~/.zshrc && zgenom update'

# Clean unused zgenom plugins
clean-plugins:
    zsh -c 'source ~/.zshrc && zgenom clean'

# Regenerate zgenom init.zsh
regen:
    rm -f ~/.zgenom/init.zsh
    zsh -c 'source ~/.zshrc'

# Show current git status
status:
    @git status --short

# Reconfigure powerlevel10k prompt
p10k:
    zsh -c 'p10k configure'

# --- Remote sync recipes ---

# Fetch changes from public GitHub repo (origin) without merging
fetch-upstream:
    git fetch origin main

# Pull changes from public GitHub repo (origin) into current branch
pull-upstream:
    git pull origin main

# Push current branch to internal work Git host
push-work:
    git push ghe main

# Sync: pull from public repo and push to work repo
sync: pull-upstream push-work
    @echo "Synced from origin (github.com) to ghe (internal work host)"

# Push to both remotes
push-all:
    git push origin main
    git push ghe main

# --- Airbnb secrets (age-encrypted at rest) ---
# claude/airbnb/rules/*.md and zsh/zsh/.zshrc.d/80-airbnb-*.zsh contain Airbnb-internal
# domains/usernames, so plaintext is gitignored and only the .age ciphertext is committed.
# Ciphertext lives under secrets/vault/ (mirroring the plaintext's relative path), not as a
# sibling of the plaintext — load-shell-fragments in zsh/zsh/.zshrc sources every readable file
# in ~/.zshrc.d with no extension filter, so a sibling .age file gets sourced as shell code.
# secrets/airbnb.recipient is the public key (encrypt, no password needed).
# secrets/airbnb-identity.age is the passphrase-sealed private key (decrypt, one password prompt).

AGE_RECIPIENT := "secrets/airbnb.recipient"
AGE_IDENTITY := "secrets/airbnb-identity.age"
AGE_VAULT := "secrets/vault"
AIRBNB_FILES := "claude/airbnb/rules/ghe-access.md claude/airbnb/rules/link-validation-airbnb.md claude/airbnb/rules/substantiate-airbnb.md zsh/zsh/.zshrc.d/80-airbnb.zsh zsh/zsh/.zshrc.d/80-airbnb-functions.zsh zsh/zsh/.zshrc.d/80-airbnb-aliases.zsh"

# Seal plaintext Airbnb files into .age ciphertext under secrets/vault/ (no password — uses the public recipient)
encrypt-airbnb:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v age >/dev/null || { echo "ERROR: age not installed (mise install age / brew install age)"; exit 1; }
    recipient="$(cat "{{ AGE_RECIPIENT }}")"
    for f in {{ AIRBNB_FILES }}; do
        if [[ ! -f "$f" ]]; then
            echo "skip (missing plaintext): $f"
            continue
        fi
        vaulted="{{ AGE_VAULT }}/$f.age"
        mkdir -p "$(dirname "$vaulted")"
        age -r "$recipient" -o "$vaulted" "$f"
        echo "sealed: $vaulted"
    done

# Unseal secrets/vault/ ciphertext into plaintext Airbnb files.
# Identity resolution order: $AIRBNB_AGE_IDENTITY (plaintext age key) ->
# ~/.config/age/airbnb-identity.txt (plaintext age key, outside the repo) ->
# secrets/airbnb-identity.age (passphrase-sealed, prompts once). The plaintext
# paths let unattended bootstrap (no TTY) unseal without a password prompt.
decrypt-airbnb:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v age >/dev/null || { echo "ERROR: age not installed (mise install age / brew install age)"; exit 1; }

    identity=""
    if [[ -n "${AIRBNB_AGE_IDENTITY:-}" && -f "${AIRBNB_AGE_IDENTITY}" ]]; then
        identity="$(cat "${AIRBNB_AGE_IDENTITY}")"
    elif [[ -f "$HOME/.config/age/airbnb-identity.txt" ]]; then
        identity="$(cat "$HOME/.config/age/airbnb-identity.txt")"
    elif [[ -t 0 ]]; then
        identity="$(age -d -o - "{{ AGE_IDENTITY }}")"
    else
        echo "==> No age identity available non-interactively — skipping Airbnb decrypt."
        echo "    Provide one via \$AIRBNB_AGE_IDENTITY or ~/.config/age/airbnb-identity.txt,"
        echo "    or run 'just decrypt-airbnb' by hand in an interactive shell."
        exit 0
    fi

    for f in {{ AIRBNB_FILES }}; do
        vaulted="{{ AGE_VAULT }}/$f.age"
        if [[ ! -f "$vaulted" ]]; then
            echo "skip (missing ciphertext): $vaulted"
            continue
        fi
        age -d -i <(printf '%s' "$identity") -o "$f" "$vaulted"
        echo "opened: $f"
    done

# One-command recovery for a stale/failed bootstrap in cloud dev environments
# that clone this repo as a bare git dir (see README "Cloud dev workspaces"
# section): re-syncs the bare repo clone at $HOME/.dotfiles against
# origin/main, then re-runs .init.sh. No-ops unless $HOME/.dotfiles is
# actually a bare git dir, so it's safe to run on a normal clone too.
repair-bare-clone:
    #!/usr/bin/env bash
    set -euo pipefail
    DOTFILES_GIT_DIR="$HOME/.dotfiles"
    if [[ ! -d "$DOTFILES_GIT_DIR" ]] \
        || [[ "$(git --git-dir="$DOTFILES_GIT_DIR" rev-parse --is-bare-repository 2>/dev/null)" != "true" ]]; then
        echo "==> $DOTFILES_GIT_DIR is not a bare git dir — nothing to repair here."
        exit 0
    fi
    echo "==> Syncing $DOTFILES_GIT_DIR against origin/main..."
    # A bare clone mirrors branches directly under refs/heads/* — there's no
    # refs/remotes/origin/* tracking namespace to reset against, so target
    # FETCH_HEAD instead, which `git fetch <remote> <ref>` always populates.
    git --git-dir="$DOTFILES_GIT_DIR" --work-tree="$HOME" fetch origin main
    git --git-dir="$DOTFILES_GIT_DIR" --work-tree="$HOME" reset --hard FETCH_HEAD
    echo "==> Re-running .init.sh..."
    "$HOME/.init.sh"

# Migrate an existing armarquez/dotfiles clone to dotfiles-v2 (see README "Migrating" section).
# dotfiles-v2 starts from a single fresh commit with no shared history, so this is a hard reset,
# not a merge — any uncommitted local changes must be committed or stashed first.
migrate-to-v2:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "ERROR: uncommitted changes present. Commit or stash before migrating." >&2
        exit 1
    fi
    echo "==> Current origin: $(git remote get-url origin)"
    git remote set-url origin git@github.com:armarquez/dotfiles-v2.git
    git fetch origin
    git checkout main
    git reset --hard origin/main
    echo "==> Migrated. origin now points to armarquez/dotfiles-v2; main reset to its history."
