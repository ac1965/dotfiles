#!/usr/bin/env bash
#
# build-emacs-macos.sh
#
# Deterministic GNU Emacs build for macOS
# - Apple Silicon / Intel 対応
# - Cocoa (Nextstep) 安定ビルド
# - Clang toolchain 使用
# - Homebrew libgccjit による native-comp
# - fingerprint 安定
# - forward-safe (Emacs 30/31)
#

set -Eeuo pipefail

# ============================================================
# Options
# ============================================================

NATIVE_COMP="--with-native-compilation=aot"
DEBUG=false

# デフォルト値（従来の挙動と同じ）
BUILD_DIR="$HOME/.local"
REPO_DIR="$HOME/Projects/github.com/emacs-mirror/emacs"

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -b, --build-dir DIR         インストール先 (--prefix) を指定 (default: $HOME/.local)
  -r, --repository-dir DIR    git clone 先ディレクトリを指定 (default: $HOME/Projects/github.com/emacs-mirror/emacs)
      --no-native, --no-native-compilation
                               native-comp を無効化
      --debug                  デバッグ出力 (set -x) を有効化
  -h, --help                   このヘルプを表示
EOF
}

# 値を取る長短オプションの両対応 ( --opt VALUE / --opt=VALUE / -o VALUE )
while [[ $# -gt 0 ]]; do
	case "$1" in
	-b | --build-dir)
		[[ $# -ge 2 ]] || {
			echo "❌ $1 requires an argument" >&2
			exit 1
		}
		BUILD_DIR="$2"
		shift 2
		;;
	--build-dir=*)
		BUILD_DIR="${1#*=}"
		shift
		;;
	-r | --repository-dir)
		[[ $# -ge 2 ]] || {
			echo "❌ $1 requires an argument" >&2
			exit 1
		}
		REPO_DIR="$2"
		shift 2
		;;
	--repository-dir=*)
		REPO_DIR="${1#*=}"
		shift
		;;
	--debug)
		DEBUG=true
		shift
		;;
	--no-native | --no-native-compilation)
		NATIVE_COMP="--without-native-compilation"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	esac
done

# 相対パス・"~" を含む可能性があるので絶対パスに正規化
BUILD_DIR="$(mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR" && pwd)"
mkdir -p "$(dirname "$REPO_DIR")"

$DEBUG && set -x

# ============================================================
# Helpers
# ============================================================

heading() {
	printf "\n\033[38;5;39m==> %s\033[0m\n\n" "$*"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "❌ required command not found: $1" >&2
		exit 1
	}
}

# ============================================================
# Platform Detection
# ============================================================

[[ "$(uname -s)" == "Darwin" ]] || {
	echo "❌ macOS only"
	exit 1
}

ARCH="$(uname -m)"

case "$ARCH" in
arm64) BREW_PREFIX="/opt/homebrew" ;;
x86_64) BREW_PREFIX="/usr/local" ;;
*)
	echo "❌ Unsupported arch: $ARCH"
	exit 1
	;;
esac

echo "Architecture: $ARCH"
echo "Homebrew prefix: $BREW_PREFIX"
echo "Build dir (--prefix): $BUILD_DIR"
echo "Repository dir: $REPO_DIR"

# ============================================================
# Requirements
# ============================================================

require_cmd brew
require_cmd git
require_cmd pkg-config
require_cmd xcrun
require_cmd clang
require_cmd ditto

BREW_FORMULAS=(
	autoconf texinfo pkg-config
	libgccjit gnutls jansson libxml2
	imagemagick tree-sitter gmp
)

heading "Installing required Homebrew packages"

for f in "${BREW_FORMULAS[@]}"; do
	brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"
done

# ============================================================
# Apple Clang Toolchain (Stable Cocoa build)
# ============================================================

heading "Configuring Apple Clang toolchain"

export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export LD="$CC"
export AR="$(xcrun --find ar)"
export RANLIB="$(xcrun --find ranlib)"
export NM="$(xcrun --find nm)"

echo "Using Clang: $CC"

# ============================================================
# SDK and Flags
# ============================================================

heading "Configuring SDK and compiler flags"

export SDKROOT="$(xcrun --show-sdk-path)"

if [[ "$ARCH" == "arm64" ]]; then
	export CFLAGS="-O3 -arch arm64 -isysroot $SDKROOT"
else
	export CFLAGS="-O3 -arch x86_64 -isysroot $SDKROOT"
fi

export CPPFLAGS="-isysroot $SDKROOT -I$BREW_PREFIX/include"
export LDFLAGS="-isysroot $SDKROOT -L$BREW_PREFIX/lib -framework AppKit"
export PKG_CONFIG_PATH="$BREW_PREFIX/lib/pkgconfig"

# ============================================================
# libgccjit for native-comp
# ============================================================

heading "Configuring libgccjit"

LIBGCCJIT_PREFIX="$(brew --prefix libgccjit)"
export CPPFLAGS="-I$LIBGCCJIT_PREFIX/include $CPPFLAGS"
export LDFLAGS="-L$LIBGCCJIT_PREFIX/lib $LDFLAGS"

# ============================================================
# Source
# ============================================================

heading "Preparing source"

SRC_REPO="https://github.com/emacs-mirror/emacs.git"
SRC_DIR="$REPO_DIR"

if [[ -d "$SRC_DIR/.git" ]]; then
	cd "$SRC_DIR"
	git pull --rebase
else
	git clone "$SRC_REPO" "$SRC_DIR"
	cd "$SRC_DIR"
fi

# ============================================================
# Clean
# ============================================================

heading "Cleaning previous build"

make distclean >/dev/null 2>&1 || true
git clean -xdf >/dev/null 2>&1 || true

# ============================================================
# Autogen
# ============================================================

heading "Running autogen"

./autogen.sh

# ============================================================
# Configure
# ============================================================

heading "Configuring Emacs"

./configure \
	CC="$CC" \
	CXX="$CXX" \
	AR="$AR" \
	RANLIB="$RANLIB" \
	NM="$NM" \
	--with-ns \
	"$NATIVE_COMP" \
	--with-tree-sitter \
	--with-json \
	--with-gnutls \
	--with-imagemagick \
	--with-modules \
	--prefix="$BUILD_DIR"

# ============================================================
# Build
# ============================================================

heading "Building Emacs"

# hw.logicalcpu だとApple Siliconの効率/性能コア混在や
# ハイパースレッディング相当の過剰な並列度により、
# gnulib/lisp生成物の依存順序でごく稀にレース由来の
# ビルド失敗(Error 2)を誘発することがあるため物理コア数を使う。
CORES="$(sysctl -n hw.physicalcpu)"

# 失敗時にエラー内容を追跡できるよう、必ずログをファイルに残す。
# tee を pipefail 下で使うため、make の終了コードは
# PIPESTATUS[0] で明示的に拾い、失敗時はログの場所を案内して即終了する。
LOGFILE="$REPO_DIR/build-$(date +%Y%m%d-%H%M%S).log"
echo "Build log: $LOGFILE"

make -j"$CORES" 2>&1 | tee "$LOGFILE"
BUILD_STATUS="${PIPESTATUS[0]}"

if [[ "$BUILD_STATUS" -ne 0 ]]; then
	echo "❌ make failed (exit $BUILD_STATUS). See log: $LOGFILE" >&2
	exit "$BUILD_STATUS"
fi

# ============================================================
# Install
# ============================================================

heading "Installing"

# nextstep/Emacs.app への Resources/lisp・MacOS/libexec の配置は
# 「make install」内(install-arch-dep / install-arch-indep)で行われる。
# 「make」(all)だけではバイナリとplist骨格しか作られないため、
# この install ステップは省略できない。
make install 2>&1 | tee -a "$LOGFILE"
INSTALL_STATUS="${PIPESTATUS[0]}"

if [[ "$INSTALL_STATUS" -ne 0 ]]; then
	echo "❌ make install failed (exit $INSTALL_STATUS). See log: $LOGFILE" >&2
	exit "$INSTALL_STATUS"
fi

# 注意: "make install" は既に $BUILD_DIR/bin に
# emacs / emacsclient (バージョン付き実体 + シンボリックリンク) を
# インストール済みのため、ここで未strip・バージョン管理外の
# 生バイナリで上書きするとインストールの整合性が崩れる。
# 意図的に上書きしたい場合のみ以下のコメントを外すこと。
#
# mkdir -p "$BUILD_DIR/bin"
# install -m 755 src/emacs "$BUILD_DIR/bin/emacs"
# install -m 755 lib-src/emacsclient "$BUILD_DIR/bin/emacsclient"

APP_DST="/Applications/Emacs.app"
rm -rf "$APP_DST"
# -L: nextstep/Emacs.app 内にシンボリックリンクが含まれていても
# 実体としてコピーし、リンク切れを防ぐ。
ditto -L nextstep/Emacs.app "$APP_DST"

# ============================================================
# Summary
# ============================================================

echo
echo "======================================="
echo "Build complete"
echo "Arch:       $ARCH"
echo "CC:         $CC"
echo "Repository: $REPO_DIR"
echo "Prefix:     $BUILD_DIR"
echo "Build log:  $LOGFILE"
echo "======================================="
