#!/bin/zsh
##
# Copyright 2020 Anthony Marquez <@boogeymarquez>
#
# BSD licensed, see LICENSE.txt in this repository.
#
# Base configuration - loaded on all machines

# Check if a command exists
function can_haz() {
  which "$@" > /dev/null 2>&1
}

# Setting up Golang environment variables
export GOPATH=$HOME/golang
export GOBIN=$GOPATH/bin

# Setting up pyenv environment variables
export PYENV_ROOT=$HOME/.pyenv

# Mac specific installed with homebrew
if can_haz mise > /dev/null; then
  export GOROOT=$(mise where go 2>/dev/null)
else
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if can_haz brew; then
      export GOROOT=$(brew --prefix golang)/libexec
    fi
  else
    export GOROOT=/usr/local/go
  fi
fi

# Conditional PATH additions
for path_candidate in $PYENV_ROOT/bin \
  ~/.local/bin \
  /usr/local/go/bin \
  $GOPATH/bin
do
  if [ -d ${path_candidate} ]; then
    export PATH="${PATH}:${path_candidate}"
  fi
done

# Setup pyenv to manage Python environments
if can_haz pyenv > /dev/null; then
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"

  if can_haz pyenv-virtualenv-init > /dev/null; then
    eval "$(pyenv virtualenv-init -)"
  fi
fi

export VIRTUAL_ENV_DISABLE_PROMPT=1
export WORKON_HOME=$HOME/.virtualenvs
export PROJECT_HOME=$HOME/Devel
export PYENV_VIRTUALENVWRAPPER_PREFER_PYVENV="true"

# Setup jenv to manage JAVA environments
export JENV_ROOT="${JENV_ROOT:=${HOME}/.jenv}"

# Lazy load jenv
if type jenv > /dev/null 2>&1; then
    export PATH="${JENV_ROOT}/bin:${JENV_ROOT}/shims:${PATH}"
    function jenv() {
        unset -f jenv
        eval "$(command jenv init -)"
        jenv $@
    }
fi

# setup rbenv to manage Ruby environments
if can_haz rbenv > /dev/null; then
  eval "$(rbenv init -)"
fi

# Adding nvm
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
if [ -d $NVM_DIR ]; then
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
fi

# Adding direnv tool
if can_haz direnv > /dev/null; then
  eval "$(direnv hook zsh)"
fi

# Check if Visual Studio Code executable exists and create symlink
if [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
    if [[ ! -h "/usr/local/bin/code" ]]; then
        ln -s "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" /usr/local/bin/code 2>/dev/null || true
    fi
fi

if is_wsl; then
  mkdir -p ~/.local/runtime && chmod 700 ~/.local/runtime
  export XDG_RUNTIME_DIR="$HOME/.local/runtime"
  export WSL_DETECTED=1
fi
