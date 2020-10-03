#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Takao Yamashita <tjy1965@gmail.com>
#

test -f ${HOME}/.${USER}_rc && source ${HOME}/.${USER}_rc
test -f ${HOME}/.docker-alias && source ${HOME}/.docker-alias

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# startship
#eval "$(starship init zsh)"

# Customize to your needs...
test -d /usr/local/opt/sqlite/bin && export PATH="/usr/local/opt/sqlite/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then
  export PYENV_ROOT="$HOME/.pyenv"
  test -d $PENV_ROOT && export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi
test -d /usr/local/opt/ruby/bin && export PATH="/usr/local/opt/ruby/bin:$PATH"
