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

for arg in "$@"; do
	case "$arg" in
	--debug) DEBUG=true ;;
	--no-native | --no-native-compilation)
		NATIVE_COMP="--without-native-compilation"
		;;
	*)
		echo "Unknown option: $arg" >&2
		exit 1
		;;
	esac
done

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

# ============================================================
# Requirements
# ============================================================

require_cmd brew
require_cmd git
require_cmd pkg-config
require_cmd xcrun
require_cmd clang

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
SRC_DIR="$HOME/Projects/github.com/emacs-mirror/emacs"

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
	--prefix="$HOME/.local"

# ============================================================
# Build
# ============================================================

heading "Building Emacs"

CORES="$(sysctl -n hw.logicalcpu)"
make -j"$CORES"

# ============================================================
# Install
# ============================================================

heading "Installing"

make install

mkdir -p "$HOME/.local/bin"
install -m 755 src/emacs "$HOME/.local/bin/emacs"
install -m 755 lib-src/emacsclient "$HOME/.local/bin/emacsclient"

APP_DST="/Applications/Emacs.app"
rm -rf "$APP_DST"
cp -R nextstep/Emacs.app "$APP_DST"

# ============================================================
# Summary
# ============================================================

echo
echo "======================================="
echo "Build complete"
echo "Arch:   $ARCH"
echo "CC:     $CC"
echo "Prefix: $HOME/.local"
echo "======================================="
