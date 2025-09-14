#!/bin/zsh
#
# aliases.refactored.zsh
# - Zsh alias/function set, organized by domain
# - Safe on macOS; Linux guards included where needed
# - Completions wired for functions (compdef)
# - Keep this file idempotent

setopt aliases

# --- Guard: interactive only ------------------------------------------------
[[ -o interactive ]] || return 0

# --- Helper: platform detection --------------------------------------------
is_macos() { [[ "$OSTYPE" == darwin* ]]; }
is_linux() { [[ "$OSTYPE" == linux* ]]; }

# --- Completion / keybind (Prezto/Oh-My-Zsh 連携前提でもOK) -----------------
# (必要に応じて外部でロードされる想定)

# --- General tools ----------------------------------------------------------
alias _='sudo'
alias please='sudo'
alias a='alias'
alias l='ls'
alias la='ls -al'
alias ll='ls -alF'
alias vi='vim'
alias quit='exit'

# Open zshrc quickly
alias zshrc='${EDITOR:-vim} "${ZDOTDIR:-$HOME}"/.zshrc'

# Quick benchmark for login shell startup (10 runs)
alias zbench='for i in {1..10}; do /usr/bin/time zsh -lic exit; done'

# --- Directory / QoL --------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias zdot='cd ${ZDOTDIR:-~}'

# Better mkcd
mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
compdef _directories mkcd

# Archive helpers
alias tarls='tar -tvf'       # usage: tarls file.tar.gz
alias untar='tar -xf'        # usage: untar file.tar.gz -C /dest

extract() {  # usage: extract archive.{tar.gz,zip,7z}
      local f="$1"
      [[ -z "$f" || ! -f "$f" ]] && { echo "usage: extract <archive>"; return 1; }
      case "$f" in
        *.tar.bz2|*.tbz2)   tar xjf "$f" ;;
        *.tar.gz|*.tgz)     tar xzf "$f" ;;
        *.tar.xz|*.txz)     tar xJf "$f" ;;
        *.tar.zst|*.tzst)   tar --zstd -xf "$f" ;;
        *.tar)              tar xf "$f" ;;
        *.zip)              unzip "$f" ;;
        *.7z)               7z x "$f" ;;
        *)                  echo "extract: unknown format: $f" ; return 2 ;;
      esac
}

# Find helpers
alias fd="find . -type d -name"
alias ff="find . -type f -name"

# URL encode/decode (python3)
urlencode() { python3 - "$@" <<'PY'
import sys, urllib.parse
for s in sys.argv[1:] or [sys.stdin.read()]:
    print(urllib.parse.quote_plus(s.strip()))
PY
}
urldecode() { python3 - "$@" <<'PY'
import sys, urllib.parse
for s in sys.argv[1:] or [sys.stdin.read()]:
    print(urllib.parse.unquote_plus(s.strip()))
PY
}

# macOS clipboard
if is_macos; then
    alias copy='pbcopy'
    alias paste='pbpaste'
fi

# ac1965
alias disablesleep='sudo pmset -a disablesleep 1'
alias enablesleep='sudo  pmset -a disablesleep 0'
alias dev='rm -f ~/.emacs.d && ln -s ~/.emacs.d-develop ~/.emacs.d'
alias prd='rm -f ~/.emacs.d && ln -s ~/.emacs.d-stable ~/.emacs.d'
alias em='open -a Emacs.app'

# --- Git short hands --------------------------------------------------------
alias g='git'
alias gs='git status -sb'
alias ga='git add -A'
alias gc='git commit -m'
alias gca='git commit -a -m'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gb='git branch -v'
alias gba='git branch -a'
alias gpl='git pull --ff-only'
alias gp='git push'
alias gpsup='git push --set-upstream origin "$(git rev-parse --abbrev-ref HEAD)"'
alias gl='git log --oneline --graph --decorate --all'
alias gfix='git commit --amend --no-edit'
alias gstash='git stash -u'
alias gpop='git stash pop'
alias gdt='git difftool'
alias gbl='git blame -w -M'

# Convenient "add+commit+push"
gacp() {
    local msg="${*:-Update}"
    git add -A && git commit -m "$msg" && git push
}
compdef _git gacp

# --- fzf (if installed) -----------------------------------------------------
if command -v fzf >/dev/null 2>&1; then
    ffz() { find "${1:-.}" -type f 2>/dev/null | fzf; }
    dfz() { find "${1:-.}" -type d 2>/dev/null | fzf; }
fi

# --- Docker aliases / functions --------------------------------------------
# (Optional external file)
[[ -f "${HOME}/.docker-alias" ]] && source "${HOME}/.docker-alias"

alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dim='docker images'
alias dprune='docker system prune -f'

dsh() { docker compose exec "${1:-}" bash; }
compdef _docker dsh
denter() { docker exec -it "$1" sh; }
compdef _docker denter
dkstopall() { docker stop $(docker ps -q); }
dkrmall() { docker rm -f $(docker ps -aq); }
dktail() {
    local name="${1:-}"
    [[ -z "$name" ]] && { echo "usage: dktail <name-pattern>"; return 1; }
    docker logs -f "$(docker ps --format '{{.Names}}' | grep -m1 "$name")"
}

# --- LLM quick helpers (Ollama) --------------------------------------------
alias oll='ollama'
alias oll-serve='ollama serve'
# quick Japanese summarize
alias oll-q='ollama run llama3 "日本語で要約して"'

# --- iTerm2 integration -----------------------------------------------------
alias iterm-bcast-on='echo "[iTerm2 Broadcast: ON] ⌘⇧I"'
alias iterm-bcast-off='echo "[iTerm2 Broadcast: OFF] ⌘⇧I"'

# --- Prompt / example hook placeholders ------------------------------------
# (left intentionally as comments for user-specific prompt integration)

# End of file
