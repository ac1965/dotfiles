
#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Takao Yamashita <tjy1965@gmail.com>
#

typeset -U path PATH

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
if [[ -s "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh" ]]; then
    source "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh"
    antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
    source ~/.zsh_plugins.zsh
    export ZSH_THEME="powerlevel10k/powerlevel10k"
fi

if command -v brew 1>/dev/null 2>&1; then
    eval "$(brew shellenv)"

    if command -v clang  1>/dev/null 2>&1; then
        export LDFLAGS="-L$(brew --prefix)/opt/llvm/lib -L$(brew --prefix)/opt/llvm/lib/c++ -Wl,-rpath,$(brew --prefix)/opt/llvm/lib/c++"
        export CPPFLAGS="-I$(brew --prefix)/opt/llvm/include"
    fi

    if command -v hub 1>/dev/null 2>&1; then
        eval "$(hub alias -s)"
    fi
    if command -v pyenv 1>/dev/null 2>&1; then
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
    fi

    test -d $(brew --prefix)/texlive/2022/bin/universal-darwin && export PATH=${PATH}/$(brew --prefix)/texlive/2022/bin/universal-darwin
fi

if command -v kubectl 1>/dev/null 2>&1; then
    source <(kubectl completion zsh)
    alias k=kubectl
    #complete -F __start_kubectl k
fi

#
[[ -f ${HOME}/.${USER}_rc ]] && source ${HOME}/.${USER}_rc
[[ -f ${HOME}/.docker-alias ]] && source ${HOME}/.docker-alias
[[ -f ${HOME}/.cargo/env ]] && source ${HOME}/.cargo/env
[[ -f ${HOME}/.asdf/asdf.sh ]] && source ${HOME}/.asdf/asdf.sh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

#
autoload -Uz compinit
compinit

zstyle ':completion:*:(rm|cp|mv|diff):*' ignore-line true
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'
