#!/usr/bin/env zsh

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
	--debug)
	    DEBUG_MODE=true
	    ;;
	--dry-run)
	    DRY_RUN=true
	    ;;
	--dry-run-log=*)
	    DRY_RUN=true
	    DRY_RUN_LOG="${arg#--dry-run-log=}"
	    ;;
	--native|--native-compilation)
	    NATIVE_COMP="--with-native-compilation"
	    ;;
	--no-native|--no-native-compilation)
	    NATIVE_COMP="--without-native-compilation"
	    ;;
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

function safe_mkdir() {
    local dir="$1"
    if $DRY_RUN; then
	echo "[dry-run] mkdir -p $dir"
    else
	mkdir -p "$dir"
    fi
}

# --- 変数定義 ---
MY_BIN="${HOME}/.local/bin"
SRC_REPOS="https://github.com/emacs-mirror/emacs.git"
TARGET="${HOME}/Projects/github.com/emacs-mirror/emacs"

typeset -a BREW_FORMULAS=(
    autoconf cmake coreutils dbus expat gcc giflib gmp gnu-sed gnutls
    jansson libffi libgccjit libiconv librsvg libtasn1 libtiff libunistring
    libxml2 little-cms2 mailutils ncurses pkg-config zlib fd git gnupg
    mupdf node openssl python ripgrep shfmt sqlite texinfo tree-sitter webp
)
typeset -a BREW_CASKS=(mactex-no-gui)

# --- Homebrew パッケージ ---
function do_brew_ensure() {
    do_heading "🔧 Homebrew パッケージを確認中..."
    run "brew update"
    run "brew install ${BREW_FORMULAS[*]} || true"
    run "brew install --cask ${BREW_CASKS[*]} || true"
    run "brew cleanup"
}

# --- CPUコア数検出 ---
CORES=$((2 * $(sysctl -n hw.ncpu)))
do_heading "💡 ${CORES} コアでビルドします"

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
  --with-xwidgets \
  --with-librsvg \
  --with-mailutils \
  --with-native-image-api \
  --with-cairo \
  --with-mac \
  --with-ns"

# --- ビルド ---
do_heading "🚀 Emacs をビルド中 (${CORES} cores)..."
run "make -j $CORES"

# --- インストール ---
do_heading "💾 Emacs をインストール中..."
run "make install"

# --- GUI アプリ起動 ---
if [[ -d "nextstep/Emacs.app" ]]; then
    run "open -R nextstep/Emacs.app"
fi

do_heading "🎉 Emacs の準備が完了しました！"
