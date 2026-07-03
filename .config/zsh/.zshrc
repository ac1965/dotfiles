#!/bin/zsh
#
# .zshrc - Zsh file loaded on interactive shell sessions.
#
# Enable Powerlevel10k instant prompt. Should stay close to the top of .zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# Lazy-load (autoload) Zsh function files from a directory.
ZFUNCDIR=${ZDOTDIR:-$HOME}/.zfunctions
if [[ -d $ZFUNCDIR ]]; then
  fpath=($ZFUNCDIR $fpath)
  autoload -Uz $ZFUNCDIR/*(.N:t)
fi
# Set any zstyles you might use for configuration.
[[ ! -f ${ZDOTDIR:-$HOME}/.zstyles ]] || source ${ZDOTDIR:-$HOME}/.zstyles
# Clone antidote if necessary.
if [[ ! -d ${ZDOTDIR:-$HOME}/.antidote ]]; then
  git clone https://github.com/mattmc3/antidote ${ZDOTDIR:-$HOME}/.antidote
fi
# Create an amazing Zsh config using antidote plugins.
# (.zshrc.d/*.zsh is now loaded via antidote path: bundles — see .zsh_plugins.txt.
#  Do NOT re-add a for-loop here; it would double-source everything.)
source ${ZDOTDIR:-$HOME}/.antidote/antidote.zsh
antidote load
# To customize prompt, run `p10k configure` or edit .p10k.zsh.
[[ ! -f ${ZDOTDIR:-$HOME}/.p10k.zsh ]] || source ${ZDOTDIR:-$HOME}/.p10k.zsh
# User define
[[ -f ${HOME}/.${USER}_rc ]] && source ${HOME}/.${USER}_rc
# .docker-alias is already sourced inside .zshrc.d/aliases.zsh — do not re-source here.
[[ -f ${HOME}/.cargo/env ]] && source ${HOME}/.cargo/env
