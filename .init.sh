#!/bin/bash
# .init.sh - Runs ONCE at initial setup
# This script sets up the dotfiles environment
set -e

# Install a CLI tool if not already present.
# Prefers mise (if available), then brew/apt/curl fallbacks.
# Usage: _ensure_tool <name> [brew_pkg] [apt_pkg]
_ensure_tool() {
    local name="$1" brew_pkg="${2:-$1}" apt_pkg="${3:-$1}"
    if command -v "$name" &>/dev/null; then
        return 0
    fi
    echo "==> '$name' not found — installing..."
    if command -v mise &>/dev/null; then
        mise install "$name" 2>/dev/null && return 0
    fi
    if command -v brew &>/dev/null; then
        brew install "$brew_pkg" 2>/dev/null && return 0
    fi
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y "$apt_pkg" 2>/dev/null && return 0
    fi
    echo "==> Warning: could not install '$name'. Install manually via mise, brew, or apt."
}

echo "==> Initializing dotfiles..."

# Suggest mise as the easiest way to get required tools, but it's optional.
# Any install path (brew, apt, manual) is fine — _ensure_tool handles all of them.
if ! command -v mise &>/dev/null; then
    echo "==> Tip: mise (https://mise.run) can bootstrap just, jq, and fzf in one step:"
    echo "         curl https://mise.run | sh"
fi

# Install zgenom if not present
if [ ! -d "$HOME/.zqs-zgenom" ] && [ ! -d "$HOME/zgenom" ]; then
    echo "==> Installing zgenom..."
    git clone https://github.com/jandamm/zgenom.git "$HOME/.zqs-zgenom" || {
        echo "==> Warning: Failed to clone zgenom (network issue?). Zsh plugins will not load until this succeeds."
    }
fi

# Use stow to symlink zsh configuration files if stow is available
# Otherwise, create symlinks manually
cd "$HOME/.dotfiles" 2>/dev/null || cd "$(dirname "$0")"

if command -v stow &> /dev/null; then
    echo "==> Using stow to symlink zsh configuration..."
    # Stow the zsh directory - this symlinks files from zsh/zsh/ to ~/
    stow --target="$HOME" --dir=zsh zsh 2>/dev/null || {
        echo "==> Stow failed, falling back to manual symlinks..."
        _manual_symlinks=true
    }
else
    echo "==> GNU stow not found, using manual symlinks..."
    _manual_symlinks=true
fi

if [ "$_manual_symlinks" = true ]; then
    # Get the directory where this script lives (the dotfiles repo)
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

    # Create symlinks for zsh configuration files
    for file in .zshrc .zsh_aliases .zsh_functions .zgen-setup; do
        if [ -f "$SCRIPT_DIR/zsh/zsh/$file" ]; then
            # Backup existing file if it's not a symlink
            if [ -f "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
                echo "==> Backing up existing $file to ${file}.bak"
                mv "$HOME/$file" "$HOME/${file}.bak"
            fi
            # Remove existing symlink if present
            [ -L "$HOME/$file" ] && rm "$HOME/$file"
            ln -sf "$SCRIPT_DIR/zsh/zsh/$file" "$HOME/$file"
            echo "==> Linked $file"
        fi
    done

    # Create .zshrc.d directory and symlink contents
    mkdir -p "$HOME/.zshrc.d"
    if [ -d "$SCRIPT_DIR/zsh/zsh/.zshrc.d" ]; then
        for file in "$SCRIPT_DIR/zsh/zsh/.zshrc.d"/*; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                [ -L "$HOME/.zshrc.d/$filename" ] && rm "$HOME/.zshrc.d/$filename"
                ln -sf "$file" "$HOME/.zshrc.d/$filename"
                echo "==> Linked .zshrc.d/$filename"
            fi
        done
    fi
fi

# Create necessary directories
mkdir -p "$HOME/.zshrc.d"
mkdir -p "$HOME/.zshrc.pre-plugins.d"
mkdir -p "$HOME/.zshrc.add-plugins.d"

# Create a pre-plugins file to configure settings before plugins load
cat > "$HOME/.zshrc.pre-plugins.d/000-workspace-config" << 'EOF'
# Workspace configuration
# Suppress powerlevel10k instant prompt warnings
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
EOF

# Disable SSH key listing/loading for cloud workspaces (uses different auth)
mkdir -p "$HOME/.zqs-settings"
echo "false" > "$HOME/.zqs-settings/list-ssh-keys"
echo "false" > "$HOME/.zqs-settings/load-ssh-keys"

# Ensure required tools are present (any installer works — mise preferred if available).
# fzf: keybindings load via the unixorn/fzf-zsh-plugin zgenom plugin; only the binary is needed.
_ensure_tool fzf
_ensure_tool just
# jq: needed at stow time (settings.json merge) and at runtime (PreToolUse hooks in settings.json).
_ensure_tool jq
# age: decrypts Airbnb-specific files (see `just decrypt-airbnb`) before Claude/zsh stow can link them.
_ensure_tool age
# delta: renders upstream diffs in 'just claude check-upstream'; falls back to plain diff if absent.
_ensure_tool delta git-delta git-delta

# just curl fallback: if _ensure_tool didn't succeed and still missing, try the upstream installer.
if ! command -v just &>/dev/null; then
    echo "==> Falling back to just upstream installer..."
    mkdir -p "$HOME/.local/bin"
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
        | bash -s -- --to "$HOME/.local/bin" 2>/dev/null || true
fi

# Seed the zsh-quickstart last-update timestamp so the first shell startup
# doesn't immediately try to git fetch/pull from GitHub.
date +%s > ~/.zsh-quickstart-last-update

# On an Airbnb machine, decrypt the sealed Airbnb-specific files before stowing
# (Claude airbnb rules + zsh 80-airbnb-*.zsh) — prompts once for the age passphrase.
if [ -d "$HOME/dev/airbnb" ] || command -v yak &>/dev/null || command -v airlab &>/dev/null || [ -d "$HOME/.airlab" ]; then
    echo "==> Airbnb environment detected — run 'just decrypt-airbnb' to unlock sealed files before stowing."
fi

# Stow Claude Code config into ~/.claude (idempotent — backs up conflicts to *.bak)
if command -v just &> /dev/null; then
    echo "==> Stowing Claude Code config..."
    just claude stow || echo "==> Warning: Claude stow failed, run 'just claude stow' manually."
fi

echo "==> Dotfiles initialization complete!"
echo "==> Your zsh configuration will be loaded on next shell startup."
