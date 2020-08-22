#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

test -f ${HOME}/.${USER}_rc && source ${HOME}/.${USER}_rc
test -f ${HOME}/.docker-alias && source ${HOME}/.docker-alias

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Customize to your needs...
test -d /usr/local/opt/sqlite/bin && export PATH="/usr/local/opt/sqlite/bin:$PATH"
export PYENV_ROOT="$HOME/.pyenv"
test -d $PYENV_ROOT && export PATH="$PYENV_ROOT/bin:$PATH" && eval "$(pyenv init -)"
