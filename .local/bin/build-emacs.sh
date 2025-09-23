#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# --- オプションパース ---
NATIVE_COMP="--with-native-compilation"
DEBUG_MODE=false
DRY_RUN=false
DRY_RUN_LOG=""

for arg in "$@"; do
    case "$arg" in
        --debug) DEBUG_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --dry-run-log=*) DRY_RUN=true; DRY_RUN_LOG="${arg#--dry-run-log=}" ;;
        --native|--native-compilation) NATIVE_COMP="--with-native-compilation" ;;
        --no-native|--no-native-compilation) NATIVE_COMP="--without-native-compilation" ;;
    esac
done

if $DEBUG_MODE; then
    echo "🔍 DEBUG モード有効"
    set -x
fi

# --- ヘルパー関数 ---
function do_heading() {
    printf "\n\033[38;5;013m * %s  \033[0m\n\n" "$*"
}

function run() {
    local cmd="$*"
    if $DRY_RUN; then
        echo "[dry-run] $cmd"
        [[ -n "$DRY_RUN_LOG" ]] && echo "$cmd" >> "$DRY_RUN_LOG"
    else
        eval "$cmd"
    fi
}

function safe_cd() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        echo "[cd] $dir"
        cd "$dir"
    else
        if $DRY_RUN; then
            echo "[dry-run] cd $dir"
        else
            echo "❌ ディレクトリが存在しません: $dir" >&2
            exit 1
        fi
    fi
}

# --- OS 判定 ---
OS=$(uname -s)
case "$OS" in
    Darwin)
        PKG_MANAGER="brew"
        CORES=$((2 * $(sysctl -n hw.ncpu)))
        INSTALL_CMD="brew install"
        EXTRA_CONFIG="--with-ns"
        ;;
    Linux)
        PKG_MANAGER="apt"
        CORES=$((2 * $(nproc)))
        INSTALL_CMD="sudo apt install -y"
        EXTRA_CONFIG="--with-xwidgets --with-cairo"
        ;;
    *)
        echo "❌ 未対応のOS: $OS" >&2
        exit 1
        ;;
esac

do_heading "💡 $OS 環境を検出 (${CORES} cores)"

# --- パッケージインストール ---
function install_packages_mac() {
    local formulas=(
        autoconf cmake coreutils dbus expat gcc giflib gmp gnu-sed gnutls
        jansson libffi libgccjit librsvg libtasn1 libtiff libunistring
        libxml2 little-cms2 mailutils ncurses pkg-config zlib fd git gnupg
        mupdf node openssl python ripgrep shfmt sqlite texinfo tree-sitter webp
    )
    local casks=(mactex-no-gui)

    do_heading "🔧 Homebrew パッケージを確認中..."

    # --- curl は常に Homebrew 版を使うが、既に入っていれば出力を抑止 ---
    if ! brew list --versions curl >/dev/null 2>&1; then
        run "brew install curl"
    fi
    run "export HOMEBREW_FORCE_BREWED_CURL=1"

    run "caffeinate -dimsu brew update"

    for f in ${formulas[@]}; do
        run "caffeinate -dimsu brew list --versions $f >/dev/null 2>&1 || caffeinate -dimsu brew install $f"
    done
    for c in ${casks[@]}; do
        run "caffeinate -dimsu brew list --cask --versions $c >/dev/null 2>&1 || caffeinate -dimsu brew install --cask $c"
    done

    run "caffeinate -dimsu brew cleanup"
}

function install_packages_ubuntu() {
    # Ubuntu（例: 22.04系）想定。libgccjit のバージョンは環境に合わせて調整可。
    local packages=(
        build-essential autoconf automake cmake gnutls-bin libgnutls28-dev
        libgtk-3-dev libjansson-dev libjpeg-dev libpng-dev libgif-dev
        libtiff-dev libncurses-dev libxpm-dev libxml2-dev libxaw7-dev
        libxft-dev libxrandr-dev libxinerama-dev libharfbuzz-dev libwebp-dev
        libgccjit-12-dev libtree-sitter-dev mailutils texinfo ripgrep
        git fd-find sqlite3 libwebkit2gtk-4.0-dev
    )

    do_heading "🔧 APT パッケージを確認中..."
    run "sudo apt update"
    run "$INSTALL_CMD ${packages[*]}"
}

if [[ "$OS" == "Darwin" ]]; then
    install_packages_mac
else
    install_packages_ubuntu
fi

# --- PKG_CONFIG_PATH 設定 ---
if [[ "$OS" == "Darwin" ]]; then
    # Homebrew prefix（Apple Silicon: /opt/homebrew, Intel: /usr/local）
    BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
    if [[ -z "${BREW_PREFIX:-}" ]]; then
        if [[ -d /opt/homebrew ]]; then
            BREW_PREFIX="/opt/homebrew"
        else
            BREW_PREFIX="/usr/local"
        fi
    fi
    # 未定義で落ちないよう ${VAR:-} を使用
    export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/gnutls/lib/pkgconfig:${BREW_PREFIX}/opt/jansson/lib/pkgconfig:${BREW_PREFIX}/opt/libxml2/lib/pkgconfig:${BREW_PREFIX}/opt/librsvg/lib/pkgconfig:${BREW_PREFIX}/opt/tree-sitter/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
else
    export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi
do_heading "📌 PKG_CONFIG_PATH = ${PKG_CONFIG_PATH:-}"

# --- 依存パッケージチェック（pkg-config） ---
if [[ "$OS" == "Darwin" ]]; then
    # NS 版 Emacs で有用な依存
    DEPENDENCIES=(gnutls jansson libxml-2.0 librsvg-2.0 tree-sitter)
else
    # Linux/GTK 版では xwidgets 対応で GTK/WebKit2GTK も確認
    DEPENDENCIES=(gtk+-3.0 webkit2gtk-4.0 gnutls jansson libxml-2.0 librsvg-2.0 tree-sitter)
fi

for dep in "${DEPENDENCIES[@]}"; do
    if ! pkg-config --exists "$dep"; then
        echo "⚠️  依存パッケージが見つかりません: $dep"
    fi
done

# --- ビルド対象 ---
MY_BIN="${HOME}/.local/bin"
SRC_REPOS="https://github.com/emacs-mirror/emacs.git"
TARGET="${HOME}/Projects/github.com/emacs-mirror/emacs"

# --- リポジトリ取得 ---
do_heading "🌐 Emacs リポジトリの準備..."
if [[ -d "$TARGET" ]]; then
    safe_cd "$TARGET"
    run "git pull --rebase"
else
    run "git clone $SRC_REPOS $TARGET"
    safe_cd "$TARGET"
fi

# --- ビルド準備 ---
do_heading "🧹 古いビルドファイルを削除..."
run "make distclean || true"
run "git clean -xdf || true"

# --- 構成 ---
do_heading "⚙️ Emacs の構成設定..."
run "./autogen.sh"
run "./configure $NATIVE_COMP \
  --with-gnutls=ifavailable \
  --with-json \
  --with-modules \
  --with-tree-sitter \
  --with-xml2 \
  --with-librsvg \
  --with-mailutils \
  --with-native-image-api \
  $EXTRA_CONFIG"

# --- ビルド ---
do_heading "🚀 Emacs をビルド中 (${CORES} cores)..."
run "make -j $CORES"

# --- インストール ---
do_heading "💾 Emacs をインストール中..."
if [[ "$OS" == "Darwin" ]]; then
    run "make install"
else
    run "sudo make install"
fi

# --- GUI 起動 ---
if [[ "$OS" == "Darwin" && -d "nextstep/Emacs.app" ]]; then
    run "open -R nextstep/Emacs.app"
elif [[ "$OS" == "Linux" ]] && command -v emacs >/dev/null 2>&1; then
    run "emacs &"
fi

do_heading "🎉 Emacs の準備が完了しました！"
