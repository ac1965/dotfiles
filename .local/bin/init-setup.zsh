#!/bin/zsh

set -o errexit
set -o nounset
set -o pipefail

# コマンド存在チェック関数
function is_installed() {
    command -v "$1" &>/dev/null
}

# Homebrew のインストール
function install_homebrew() {
    if ! is_installed brew; then
        echo "🧰 Command Line Tools をインストールします..."
        xcode-select --install || echo "すでにインストール済みかもしれません"

        echo "🍺 Homebrew をインストールします..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo "✅ Homebrew のインストール完了"
    else
        echo "✅ Homebrew はすでにインストール済みです"
    fi
}

# アプリケーションのインストール（--cask）
function install_cask_app() {
    local app_name="$1"
    local app_path="/Applications/${2}"

    if [[ ! -d "$app_path" ]]; then
        echo "📦 ${app_name} をインストールします..."
        brew install --cask "$app_name"
        echo "✅ ${app_name} のインストール完了"
    else
        echo "✅ ${app_name} はすでにインストール済みです"
    fi
}

# 実行
install_homebrew
install_cask_app "iterm2" "iTerm.app"
