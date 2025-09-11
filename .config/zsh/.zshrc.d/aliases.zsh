#!/bin/zsh
#
# .aliases - Set whatever shell aliases you want.
#

# single character aliases - be sparing!
alias _=sudo
alias a=alias
alias l=ls
alias g=git

# mask built-ins with better defaults
alias vi=vim

# fix common typos
alias quit='exit'

# tar
alias tarls="tar -tvf"
alias untar="tar -xf"

# find
alias fd='find . -type d -name'
alias ff='find . -type f -name'

# url encode/decode
alias urldecode='python3 -c "import sys, urllib.parse as ul; \
    print(ul.unquote_plus(sys.argv[1]))"'
alias urlencode='python3 -c "import sys, urllib.parse as ul; \
    print (ul.quote_plus(sys.argv[1]))"'

# misc
alias please=sudo
alias zshrc='${EDITOR:-vim} "${ZDOTDIR:-$HOME}"/.zshrc'
alias zbench='for i in {1..10}; do /usr/bin/time zsh -lic exit; done'
alias zdot='cd ${ZDOTDIR:-~}'

# =========================
if [[ -r "${HOME}/.p10k.zsh" ]]; then
  source "${HOME}/.p10k.zsh"
fi

# --- Completion / keybind (Prezto連携)
autoload -Uz compinit; compinit -u
bindkey -e

# --- iTerm2 integration
# クリップボードへパイプ： pbcopy / pbpaste
alias copy='pbcopy'
alias paste='pbpaste'

# --- General tools
export EDITOR="nvim"
export PAGER="less -R"

# --- fzf (あれば)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --- Docker aliases（別ファイルを読み込む: ~/.docker-alias）
[ -f ~/.docker-alias ] && source ~/.docker-alias

# --- LLM quick helpers (Ollama)
alias oll='ollama'
alias oll-serve='ollama serve'
# 代表モデル例： llama3（名称は手元に合わせて）
alias oll-q='ollama run llama3 "日本語で要約して"'

# --- Git short hands
alias gs='git status -sb'
alias ga='git add -A'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --all'

# --- Directory / quality of life
alias ll='ls -alF'
alias ..='cd ..'
alias ...='cd ../..'

# --- Prompt に Docker 情報を埋め込みたい場合の関数例
docker_branch() {
  # 稼働中コンテナ数を表示 (重い場合は間引き推奨)
  local n; n=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  [[ "$n" != "0" ]] && echo "🐳${n}"
}
# Powerlevel10k の custom segment で $(docker_branch) を描画しても良い

# --- iTerm2: 放送入力を使う時の表示ヒント
alias iterm-bcast-on='echo "[iTerm2 Broadcast: ON] ⌘⇧I"'
alias iterm-bcast-off='echo "[iTerm2 Broadcast: OFF] 再度 ⌘⇧I"'

# =========================
# Docker aliases & helpers
# =========================

# Compose 基本
alias dkup='docker compose up -d'
alias dkdown='docker compose down'
alias dkps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dkimg='docker images'
alias dknet='docker network ls'
alias dkvol='docker volume ls'
alias dkstats='docker stats'     # リソース監視（終了: Ctrl+C）

# Logs
# 例: dklf web   → サービス web のフォロー表示
dklf() { docker compose logs -f --tail=200 "${1:-}"; }

# Exec / shell
# 例: dksh web   → サービス web に sh で入る
dksh() { docker compose exec "${1:-}" sh; }
dkbash() { docker compose exec "${1:-}" bash; }

# Into コンテナ ID 指定派
# 例: denter <container_id>
denter() { docker exec -it "$1" sh; }

# Prune（要注意: 未使用リソースを全掃除）
alias dkprune='docker system prune -af --volumes'

# Stop/Remove all（危険操作: 明示確認）
dkstopall() { docker stop $(docker ps -q); }
dkrmall()   { docker rm -f $(docker ps -aq); }

# Build / Recreate
alias dkbuild='docker compose build --no-cache'
alias dkreup='docker compose up -d --force-recreate'

# Tail 特定コンテナ（docker ps 名前一致）
dktail() {
  local name="${1:-}"
  [[ -z "$name" ]] && { echo "usage: dktail <name-pattern>"; return 1; }
  docker logs -f --tail=200 "$(docker ps --format '{{.Names}}' | grep -m1 "$name")"
}

# オーケストレーション: ペイン分割運用の想定
# 左: dklf <svc> / 右上: dkstats / 右下: ollama run ...

# ac1965
alias disablesleep='sudo pmset -a disablesleep 1'
alias enablesleep='sudo  pmset -a disablesleep 0'
alias la='ls -al'
alias dev='rm -f ~/.emacs.d && ln -s ~/.emacs.d-develop ~/.emacs.d'
alias prd='rm -f ~/.emacs.d && ln -s ~/.emacs.d-stable ~/.emacs.d'
alias em='open -a Emacs.app'
