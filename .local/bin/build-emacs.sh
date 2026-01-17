 #!/usr/bin/env bash
#
# build-emacs-macos.sh
#
# Build GNU Emacs from source on macOS (CLI + GUI unified)
# - native-comp supported
# - Homebrew based
#
# Result:
#   CLI : ~/.local/bin/emacs        -> Emacs.app/Contents/MacOS/Emacs
#   CLI : ~/.local/bin/emacsclient  -> Emacs.app/Contents/MacOS/bin/emacsclient
#   GUI : /Applications/Emacs.app
#

set -Eeuo pipefail

# ============================================================
# Options
# ============================================================
NATIVE_COMP="--with-native-compilation"
DEBUG=false
DRY_RUN=false
DRY_RUN_LOG=""

for arg in "$@"; do
  case "$arg" in
    --debug)
      DEBUG=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --dry-run-log=*)
      DRY_RUN=true
      DRY_RUN_LOG="${arg#--dry-run-log=}"
      ;;
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

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
    [[ -n "$DRY_RUN_LOG" ]] && echo "$*" >> "$DRY_RUN_LOG"
  else
    "$@"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ required command not found: $1" >&2
    exit 1
  }
}

# ============================================================
# Environment detection
# ============================================================
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
  echo "❌ This script supports macOS only." >&2
  exit 1
fi

CORES="$(sysctl -n hw.logicalcpu)"

heading "Detected macOS (${CORES} cores)"

require_cmd brew
require_cmd git
require_cmd pkg-config

# ============================================================
# Homebrew dependencies
# ============================================================
heading "Checking Homebrew dependencies"

BREW_FORMULAS=(
  autoconf
  gcc
  libgccjit
  gnutls
  pkg-config
  texinfo
  jansson
  libxml2
  imagemagick
  tree-sitter
)

for f in "${BREW_FORMULAS[@]}"; do
  run brew list --versions "$f" >/dev/null 2>&1 || run brew install "$f"
done

# ============================================================
# PKG_CONFIG_PATH
# ============================================================
BREW_PREFIX="$(brew --prefix)"
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/libgccjit/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

heading "PKG_CONFIG_PATH"
echo "$PKG_CONFIG_PATH"

# ============================================================
# Paths
# ============================================================
SRC_REPO="https://github.com/emacs-mirror/emacs.git"
SRC_DIR="${HOME}/Projects/github.com/emacs-mirror/emacs"
PREFIX="${HOME}/.local"
APP_DST="/Applications/Emacs.app"

CLI_BIN="${PREFIX}/bin/emacs"
CLI_CLIENT_BIN="${PREFIX}/bin/emacsclient"

APP_BIN="${APP_DST}/Contents/MacOS/Emacs"
APP_CLIENT_BIN="${APP_DST}/Contents/MacOS/bin/emacsclient"

# ============================================================
# Fetch source
# ============================================================
heading "Preparing Emacs source"

if [[ -d "$SRC_DIR/.git" ]]; then
  cd "$SRC_DIR"
  run git pull --rebase
else
  run git clone "$SRC_REPO" "$SRC_DIR"
  cd "$SRC_DIR"
fi

# ============================================================
# Clean
# ============================================================
heading "Cleaning previous build artifacts"
run make distclean || true
run git clean -xdf || true

# ============================================================
# Configure
# ============================================================
heading "Configuring Emacs"

run ./autogen.sh

run ./configure \
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
heading "Building Emacs"
run make -j"$CORES"

# ============================================================
# Install CLI support files (lisp, etc, emacsclient)
# ============================================================
heading "Installing CLI support files"
run make install

# ============================================================
# Install GUI app
# ============================================================
heading "Installing Emacs.app"

if [[ -d nextstep/Emacs.app ]]; then
  run rm -rf "$APP_DST"
  run cp -R nextstep/Emacs.app "$APP_DST"
else
  echo "❌ Emacs.app not found. Build failed?" >&2
  exit 1
fi

# ============================================================
# Symlink CLI binaries to Emacs.app
# ============================================================
heading "Linking CLI binaries to Emacs.app"

run mkdir -p "$(dirname "$CLI_BIN")"

if [[ -x "$APP_BIN" ]]; then
  run ln -sf "$APP_BIN" "$CLI_BIN"
else
  echo "❌ Emacs.app binary not found: $APP_BIN" >&2
  exit 1
fi

if [[ -x "$APP_CLIENT_BIN" ]]; then
  run ln -sf "$APP_CLIENT_BIN" "$CLI_CLIENT_BIN"
else
  echo "❌ emacsclient not found in Emacs.app: $APP_CLIENT_BIN" >&2
  exit 1
fi

# ============================================================
# Result
# ============================================================
heading "Build completed successfully"

echo "CLI emacs       : $CLI_BIN -> $APP_BIN"
echo "CLI emacsclient : $CLI_CLIENT_BIN -> $APP_CLIENT_BIN"
echo "GUI             : $APP_DST"
echo
echo "Run:"
echo "  emacs"
echo "  emacsclient -c"
echo "  open $APP_DST"
echo
echo "🎉 Emacs build finished successfully"
