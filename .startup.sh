#!/bin/bash
# .startup.sh - Runs EVERY time the workspace starts or resumes
# Use for ephemeral setup that won't persist after workspace pause
set -e

echo "==> Running dotfiles startup script..."

# Put mise shims and ~/.local/bin on PATH first — the self-heal check below
# needs 'just' on PATH, and tools installed by .init.sh may live there.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
if command -v mise &> /dev/null; then
    eval "$(mise activate bash 2>/dev/null)" 2>/dev/null || true
fi

# Some cloud dev environments only run .init.sh on a brand-new workspace,
# never on resume — so a workspace that failed its first bootstrap (or was
# recloned manually after one did) can never self-heal on restart. Detect
# "not stowed" here instead and re-run .init.sh ourselves; report failure
# without aborting the rest of startup.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -L "$HOME/.zshrc" ] || [ ! -f "$HOME/.claude/settings.json" ]; then
    echo "==> Dotfiles not fully stowed — running .init.sh..."
    "$SCRIPT_DIR/.init.sh" || echo "==> Warning: .init.sh failed, run it manually: $SCRIPT_DIR/.init.sh"
fi

# Ensure zsh is the default shell if not already
if [ "$SHELL" != "$(command -v zsh)" ] && command -v zsh &> /dev/null; then
    echo "==> Note: Default shell is not zsh. Run 'chsh -s $(command -v zsh)' to change it."
fi

# Ensure zgenom plugin directory exists (may be lost on pause)
if [ ! -d "$HOME/.zgenom" ]; then
    mkdir -p "$HOME/.zgenom"
fi

# Source yak completion if yak is available
if command -v yak &> /dev/null; then
    echo "==> yak CLI detected"
fi

echo "==> Startup script complete!"
