#!/bin/bash
# .init.sh - Runs ONCE at initial setup
# This script sets up the dotfiles environment
set -e

# Resolve the repo root from this script's own location — never from
# $HOME/.dotfiles. Some cloud dev environments clone this repo bare to
# $HOME/.dotfiles with work-tree=$HOME, so the repo's files (including this
# script) live directly under $HOME; $HOME/.dotfiles itself is only the bare
# git dir and has no zsh/, claude/, or justfile.
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$REPO_ROOT/justfile" ] || [ ! -d "$REPO_ROOT/zsh/zsh" ]; then
    echo "==> ERROR: '$REPO_ROOT' doesn't look like a dotfiles checkout (missing justfile or zsh/zsh)." >&2
    exit 1
fi
cd "$REPO_ROOT"

echo "==> Initializing dotfiles from $REPO_ROOT..."

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

# Suggest mise as the easiest way to get required tools, but it's optional.
# Any install path (brew, apt, manual) is fine — _ensure_tool handles all of them.
if ! command -v mise &>/dev/null; then
    echo "==> Tip: mise (https://mise.run) can bootstrap just, jq, and fzf in one step:"
    echo "         curl https://mise.run | sh"
fi

# Put mise shims and ~/.local/bin on PATH for the rest of this script — tools
# installed below by mise or the just curl fallback land there, not in a
# default unattended-bootstrap PATH.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# Ensure required tools are present (any installer works — mise preferred if available).
# stow: symlinks the zsh/ and claude/ packages below; must be present before stowing.
_ensure_tool stow
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

# Everything below drives itself through 'just' — fail loudly rather than
# silently skipping stow/decrypt steps if it's still missing.
if ! command -v just &>/dev/null; then
    echo "==> ERROR: 'just' is required but could not be installed automatically." >&2
    echo "==> Install manually (https://just.systems/install.sh) and re-run this script." >&2
    exit 1
fi

# Install zgenom if not present
if [ ! -d "$HOME/.zqs-zgenom" ] && [ ! -d "$HOME/zgenom" ]; then
    echo "==> Installing zgenom..."
    git clone https://github.com/jandamm/zgenom.git "$HOME/.zqs-zgenom" || {
        echo "==> Warning: Failed to clone zgenom (network issue?). Zsh plugins will not load until this succeeds."
    }
fi

# Decrypt Airbnb-specific files before stowing, so the Airbnb rules/fragments
# exist to be linked below. Non-interactive when $AIRBNB_AGE_IDENTITY or
# ~/.config/age/airbnb-identity.txt is present; otherwise prompts once, or
# skips cleanly (with instructions) if there's no TTY.
just decrypt-airbnb || echo "==> Warning: decrypt-airbnb failed, run 'just decrypt-airbnb' manually."

# Symlink zsh + Claude config via stow. Falls back to manual symlinks (with
# backups of any pre-existing real files, e.g. a base-image ~/.zshrc) if
# stow is unavailable or fails.
_manual_symlinks=false
if command -v stow &>/dev/null; then
    echo "==> Using stow to symlink dotfiles..."
    if ! just stow; then
        echo "==> 'just stow' failed, falling back to manual symlinks..."
        _manual_symlinks=true
    fi
else
    echo "==> GNU stow not found, using manual symlinks..."
    _manual_symlinks=true
fi

if [ "$_manual_symlinks" = true ]; then
    # Zsh package: link the top-level dotfiles and .zshrc.d fragments directly.
    for file in .zshrc .zsh_aliases .zsh_functions .zgen-setup; do
        src="$REPO_ROOT/zsh/zsh/$file"
        [ -f "$src" ] || continue
        target="$HOME/$file"
        if [ -f "$target" ] && [ ! -L "$target" ]; then
            echo "==> Backing up existing $file to ${file}.pre-dotfiles.bak"
            mv "$target" "${target}.pre-dotfiles.bak"
        fi
        [ -L "$target" ] && rm "$target"
        ln -sf "$src" "$target"
        echo "==> Linked $file"
    done

    mkdir -p "$HOME/.zshrc.d"
    if [ -d "$REPO_ROOT/zsh/zsh/.zshrc.d" ]; then
        for src in "$REPO_ROOT/zsh/zsh/.zshrc.d"/*; do
            [ -f "$src" ] || continue
            filename=$(basename "$src")
            target="$HOME/.zshrc.d/$filename"
            [ -L "$target" ] && rm "$target"
            ln -sf "$src" "$target"
            echo "==> Linked .zshrc.d/$filename"
        done
    fi

    # Claude package: stow isn't available, so link base (and, on an Airbnb
    # env, airbnb) rules/config directly, then regenerate settings.json via
    # jq — gen-settings only needs jq, not stow.
    echo "==> Linking Claude Code config manually..."
    mkdir -p "$HOME/.claude/rules"
    for file in CLAUDE.md statusline.sh; do
        src="$REPO_ROOT/claude/base/$file"
        [ -f "$src" ] || continue
        target="$HOME/.claude/$file"
        if [ -f "$target" ] && [ ! -L "$target" ]; then
            mv "$target" "${target}.pre-dotfiles.bak"
        fi
        [ -L "$target" ] && rm "$target"
        ln -sf "$src" "$target"
    done
    for src in "$REPO_ROOT/claude/base/rules/"*.md; do
        [ -f "$src" ] || continue
        target="$HOME/.claude/rules/$(basename "$src")"
        if [ -f "$target" ] && [ ! -L "$target" ]; then
            mv "$target" "${target}.pre-dotfiles.bak"
        fi
        [ -L "$target" ] && rm "$target"
        ln -sf "$src" "$target"
    done
    if [ -d "$HOME/dev/airbnb" ] || command -v yak &>/dev/null || command -v airlab &>/dev/null || [ -d "$HOME/.airlab" ]; then
        for src in "$REPO_ROOT/claude/airbnb/rules/"*.md; do
            [ -f "$src" ] || continue
            target="$HOME/.claude/rules/$(basename "$src")"
            if [ -f "$target" ] && [ ! -L "$target" ]; then
                mv "$target" "${target}.pre-dotfiles.bak"
            fi
            [ -L "$target" ] && rm "$target"
            ln -sf "$src" "$target"
        done
    fi
    just claude gen-settings || echo "==> Warning: could not generate ~/.claude/settings.json"
else
    echo "==> Stowing Claude Code config..."
    just claude stow || echo "==> Warning: Claude stow failed, run 'just claude stow' manually."
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

# Seed the zsh-quickstart last-update timestamp so the first shell startup
# doesn't immediately try to git fetch/pull from GitHub.
date +%s > ~/.zsh-quickstart-last-update

echo "==> Dotfiles initialization complete!"
echo "==> Your zsh configuration will be loaded on next shell startup."
