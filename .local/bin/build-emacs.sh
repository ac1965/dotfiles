#!/usr/bin/env bash

set -euo pipefail

### 📝 引数の解析：ネイティブコンパイルの切り替え
NATIVE_COMP="--with-native-compilation"  # デフォルトはネイティブコンパイル有効
for arg in "$@"; do
    case $arg in
        --native|--native-compilation)
            NATIVE_COMP="--with-native-compilation"
            ;;
        --no-native|--no-native-compilation)
            NATIVE_COMP="--without-native-compilation"
            ;;
    esac
done

### 🌐 変数設定
MY_BIN="${HOME}/.local/bin"
SRC_REPOS="https://github.com/emacs-mirror/emacs.git"
TARGET="${HOME}/Projects/github.com/emacs-mirror/emacs"
BREW_FORMULAS=(
    autoconf cmake coreutils dbus expat gcc giflib gmp gnu-sed gnutls
    jansson libffi libgccjit libiconv librsvg libtasn1 libtiff libunistring
    libxml2 little-cms2 mailutils ncurses pkg-config zlib fd git gnupg
    mupdf node openssl python ripgrep shfmt sqlite texinfo tree-sitter webp
)
BREW_CASKS=(mactex-no-gui)

### 💡 ヘッダー表示関数
do_heading() {
    printf "\n\033[38;5;013m * %s  \033[0m  \n\n" "$*"
}

### 🍺 Homebrew パッケージの確認・インストール
do_brew_ensure() {
    do_heading "🔧 Ensuring Homebrew packages..."
    brew update
    brew install "${BREW_FORMULAS[@]}" || true
    brew install --cask "${BREW_CASKS[@]}" || true
    brew cleanup
}

### ⚡ CPU コア数を自動検出
CORES=$((2 * $(sysctl -n hw.ncpu)))
do_heading "💡 Using ${CORES} CPU cores for compilation."

### 📥 Emacs リポジトリのクローンまたは更新
do_heading "🌐 Cloning or updating Emacs repository..."
if [ -d "${TARGET}" ]; then
    cd "${TARGET}" || exit
    git pull --rebase
else
    git clone "${SRC_REPOS}" "${TARGET}"
    cd "${TARGET}" || exit
fi

### 🔧 ビルドのクリーンアップ
do_heading "🧹 Cleaning old build files..."
make distclean || true
git clean -xdf || true

### 🚀 Emacs の構成設定
do_heading "⚙️ Configuring Emacs build..."
./autogen.sh
./configure $NATIVE_COMP \
    --with-gnutls=ifavailable \
    --with-json \
    --with-modules \
    --with-tree-sitter \
    --with-xml2 \
    --with-xwidgets \
    --with-librsvg \
    --with-mailutils \
    --with-native-image-api \
    --with-cairo

### 🚀 ビルド開始
do_heading "🚀 Building Emacs with ${CORES} cores..."
make -j "${CORES}"

### 🚀 インストール
do_heading "💾 Installing Emacs..."
sudo make install

### 📂 GUI Emacs.app を開く（GUI ビルドの場合）
if [ -d "nextstep/Emacs.app" ]; then
    sudo open -R nextstep/Emacs.app
fi

### ✅ インストール後の確認
do_heading "✅ Emacs build and installation complete!"
emacs --version

### 🌐 Emacs バイナリのパス設定
if [ -d "/Applications/Emacs.app" ]; then
    sudo ln -sf /Applications/Emacs.app/Contents/MacOS/Emacs /usr/local/bin/emacs
    sudo ln -sf /Applications/Emacs.app/Contents/MacOS/bin/emacsclient /usr/local/bin/emacsclient
    do_heading "✅ Emacs is linked in /usr/local/bin."
fi

### 🔧 環境変数設定（exec-path-from-shell）
do_heading "🌐 Setting up environment variables for Emacs (exec-path-from-shell)..."
if [ -f "${HOME}/.zshrc" ]; then
    shell_profile="${HOME}/.zshrc"
elif [ -f "${HOME}/.bash_profile" ]; then
    shell_profile="${HOME}/.bash_profile"
fi

if ! grep -q 'exec-path-from-shell-initialize' "${shell_profile}"; then
    echo 'eval "$(exec-path-from-shell-initialize)"' >> "${shell_profile}"
    do_heading "✅ Added exec-path-from-shell to ${shell_profile}."
fi

do_heading "🎉 Emacs is ready to use!"

