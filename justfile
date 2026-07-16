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

# Symlink dotfiles using stow
stow:
    cd zsh && stow --target="$HOME" zsh

# Remove symlinks created by stow
unstow:
    cd zsh && stow --delete --target="$HOME" zsh

# Re-stow (useful after adding new files)
restow:
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

# Unseal secrets/vault/ ciphertext into plaintext Airbnb files (prompts once for the passphrase)
decrypt-airbnb:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v age >/dev/null || { echo "ERROR: age not installed (mise install age / brew install age)"; exit 1; }
    identity="$(age -d -o - "{{ AGE_IDENTITY }}")"
    for f in {{ AIRBNB_FILES }}; do
        vaulted="{{ AGE_VAULT }}/$f.age"
        if [[ ! -f "$vaulted" ]]; then
            echo "skip (missing ciphertext): $vaulted"
            continue
        fi
        age -d -i <(printf '%s' "$identity") -o "$f" "$vaulted"
        echo "opened: $f"
    done

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
