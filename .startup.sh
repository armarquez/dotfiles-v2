#!/bin/bash
# .startup.sh - Runs EVERY time the workspace starts or resumes
# Use for ephemeral setup that won't persist after workspace pause
set -e

echo "==> Running dotfiles startup script..."

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

# Ensure mise shims are in PATH for this session
if [ -d "$HOME/.local/share/mise/shims" ]; then
    export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

# Activate mise if available
if command -v mise &> /dev/null; then
    eval "$(mise activate bash 2>/dev/null)" 2>/dev/null || true
fi

echo "==> Startup script complete!"
