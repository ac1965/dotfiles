#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Takao Yamashita <tjy1965@gmail.com>
#

typeset -U path PATH

test -f ${HOME}/.${USER}_rc && source ${HOME}/.${USER}_rc
test -f ${HOME}/.docker-alias && source ${HOME}/.docker-alias
test -f ${HOME}/.cargo/env && source ${HOME}/.cargo/env
test -f ${HOME}/.asdf/asdf.sh && . ${HOME}/.asdf/asdf.sh

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
    source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# startship
#eval "$(starship init zsh)"

# Customize to your needs...
test -d /usr/local/texlive/2022/bin/universal-darwin && export PATH="/usr/local/texlive/2022/bin/universal-darwin:${PATH}"

if command -v pyenv 1>/dev/null 2>&1; then
    export PYENV_ROOT="${HOME}/.pyenv"
    test -d ${PENV_ROOT} && export PATH="${PYENV_ROOT}/bin:${PATH}"
    eval "$(pyenv init -)"
fi
if command -v hub 1>/dev/null 2>&1; then
    eval "$(hub alias -s)"
fi
if command -v kubectl 1>/dev/null 2>&1; then
    source <(kubectl completion zsh)
    alias k=kubectl
    #complete -F __start_kubectl k
fi
