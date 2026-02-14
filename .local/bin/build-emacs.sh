#!/usr/bin/env bash
#
# build-emacs-macos.sh
#
# Build GNU Emacs on macOS (CLI + GUI, clean separation)
#

set -Eeuo pipefail

# ============================================================
# Options
# ============================================================
NATIVE_COMP="--with-native-compilation"
DEBUG=false

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
    --no-native|--no-native-compilation)
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

run() { "$@"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ required command not found: $1" >&2
    exit 1
  }
}

# ============================================================
# Environment
# ============================================================
[[ "$(uname -s)" == "Darwin" ]] || {
  echo "❌ macOS only" >&2
  exit 1
}

CORES="$(sysctl -n hw.logicalcpu)"

require_cmd brew
require_cmd git
require_cmd pkg-config

# ============================================================
# Homebrew deps
# ============================================================
heading "Homebrew dependencies"

BREW_FORMULAS=(
  autoconf gcc libgccjit gnutls pkg-config
  texinfo jansson libxml2 imagemagick tree-sitter
)

for f in "${BREW_FORMULAS[@]}"; do
  brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"
done

BREW_PREFIX="$(brew --prefix)"
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/libgccjit/lib/pkgconfig"

export CC=clang
export LIBRARY_PATH="$BREW_PREFIX/lib/gcc/15"
export CPATH="$BREW_PREFIX/include"
export DYLD_LIBRARY_PATH="$BREW_PREFIX/lib/gcc/15"

# ============================================================
# Paths
# ============================================================
SRC_REPO="https://github.com/emacs-mirror/emacs.git"
SRC_DIR="${HOME}/Projects/github.com/emacs-mirror/emacs"

PREFIX="${HOME}/.local"
CLI_BIN="${PREFIX}/bin"
APP_DST="/Applications/Emacs.app"

# ============================================================
# Fetch
# ============================================================
heading "Fetching source"

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
heading "Cleaning"
make distclean || true
git clean -xdf || true

# ============================================================
# Configure
# ============================================================
heading "Configuring"

./autogen.sh

./configure \
  --with-ns \
  --enable-mac-app=yes \
  --with-xwidgets \
  "$NATIVE_COMP" \
  --with-json \
  --with-tree-sitter \
  --with-imagemagick \
  --with-gnutls \
  --prefix="$PREFIX"

# ============================================================
# Build
# ============================================================
heading "Building"
make -j"$CORES"

# ============================================================
# Install (data only)
# ============================================================
heading "Installing lisp / etc"
make install

# ============================================================
# Install CLI from src/emacs (重要)
# ============================================================
heading "Installing CLI emacs from src/emacs"

mkdir -p "$CLI_BIN"

if [[ -x src/emacs ]]; then
  install -m 755 src/emacs       "$CLI_BIN/emacs"
  install -m 755 lib-src/emacsclient "$CLI_BIN/emacsclient"
else
  echo "❌ src/emacs not found" >&2
  exit 1
fi

# ============================================================
# Install GUI app
# ============================================================
heading "Installing Emacs.app"

if [[ -d nextstep/Emacs.app ]]; then
  rm -rf "$APP_DST"
  cp -R nextstep/Emacs.app "$APP_DST"
else
  echo "❌ Emacs.app not built" >&2
  exit 1
fi

# ============================================================
# Result
# ============================================================
heading "Done"

echo "CLI:"
echo "  $CLI_BIN/emacs"
echo "  $CLI_BIN/emacsclient"
echo
echo "GUI:"
echo "  $APP_DST"
echo
echo "Usage:"
echo "  emacs            # CLI"
echo "  emacs --batch    # batch / make / CI"
echo "  open $APP_DST    # GUI"
echo "  emacsclient -c   # GUI client"
