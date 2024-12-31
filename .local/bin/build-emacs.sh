#! /usr/bin/env bash

# Parse arguments for native compilation toggle
NATIVE_COMP="--without-native-compilation" # Default
for arg in "$@"; do
    case $arg in
        --native-compilation)
        NATIVE_COMP="--with-native-compilation=aot"
        shift
        ;;
        --no-native-compilation)
        NATIVE_COMP="--without-native-compilation"
        shift
        ;;
    esac
done

MY_BIN="${HOME}/.local/bin"

DO_BREW_PACKAGES=(
    # Build dependencies
    autoconf
    cmake
    coreutils
    dbus
    expat
    gcc
    giflib
    gmp
    gnu-sed
    gnutls
    jansson
    libffi
    libgccjit
    libiconv
    librsvg
    libtasn1
    libtiff
    libunistring
    libxml2
    little-cms2
    mailutils
    ncurses
    pkgconf
    zlib

    # Runtime dependencies
    fd
    git
    gnupg
    mupdf
    node
    openssl
    python
    ripgrep
    shfmt
    sqlite
    texinfo
    tree-sitter
    webp
)

DO_BREW_CASKS=(
    mactex-no-gui
)

#    --with-cairo
#    --without-ns
#    --with-cocoa
DO_CONFIGURE_OPTS=(
    --with-gnutls=ifavailable
    --with-json
    --with-modules
    --with-tree-sitter=ifavailable
    --with-xml2
    --with-xwidgets
    --with-librsvg
)

# Print the given arguments out in a nice heading
do_heading() {
    printf "\n\033[38;5;013m * %s  \033[0m  \n\n" "$*"
}

# Return exit code 0 if $1 is the same as any of the rest of the arguments
contains() {
    local e match="$1"
    shift
    for e in "$@"; do [ "$e" = "$match" ] && return 0; done
    return 1
}

# Ensure the given homebrew packages are installed and up to date
# brew_ensure [ cask ] dep1 [ dep2 ] [ ... ]
do_brew_ensure() {
    do_heading "Ensuring Homebrew packages..."
    echo "$@"
    local brew_type installed required missing outdated upgrade
    brew_type="$1"
    shift

    # List installed packages
    installed=($(brew list $brew_type -q))
    # strip off the "@version" part, e.g. "python@3.9" becomes "python"
    for i in "${!installed[@]}"; do
        installed[$i]="${installed[$i]%%@*}"
    done

    # List missing packages (required but not installed)
    required=("$@")
    missing=()
    for p in "${required[@]}"; do
        contains "$p" "${installed[@]}" || missing+=("$p")
    done

    # Install missing packages
    if [ -n "${missing[*]:-}" ]; then
        echo "Installing packages: ${missing[*]}"
        brew install $brew_type "${missing[@]}"
    fi

    # List of outdated packages
    outdated="$(brew outdated $brew_type -q)"
    upgrade=()
    for p in "${required[@]}"; do
        contains "$p" "${outdated[@]}" && upgrade+=("$p")
    done

    # Upgrade out outdated packages
    if [ -n "${upgrade[*]:-}" ]; then
        echo "Upgrading packages: ${upgrade[*]}"
        brew upgrade $brew_type "${upgrade[@]}"
    fi
}

# Print the number of CPU cores on the local machine
do_how_many_cores() {
    case "$(uname)" in
        Darwin)
            sysctl -n hw.ncpu
            ;;
        Linux)
            awk '/^processor/ {++n} END {print n}' /proc/cpuinfo
            ;;
    esac
}

SRC_REPOS="https://github.com/emacs-mirror/emacs.git"
TARGET="${GITHUB_REPOS}/github.com/emacs-mirror/emacs"

do_heading "Pulling Git ${SRC_REPOS}"
test -x ${MY_BIN}/hub-clone.sh || exit 9
if [ -d "${TARGET}" ]; then
    cd "${TARGET}" || exit
    git reset --hard
    git clean -xdf
    git pull
else
    ${MY_BIN}/hub-clone.sh "${SRC_REPOS}" # https://github.com/emacs-mirror/emacs.git
fi

DO_CORES=$((2 * $(do_how_many_cores)))
do_brew_ensure --formula "${DO_BREW_PACKAGES[@]}"
do_brew_ensure --cask "${DO_BREW_CASKS[@]}"

# cd "$(brew --prefix)/lib"
# ln -s ../Cellar/libgccjit/12.2.0/lib/gcc/12/libgccjit.dylib ./
# ln -s ../Cellar/libgccjit/12.2.0/lib/gcc/12/libgccjit.0.dylib ./
# ln -s ../Cellar/gcc/14.1.0/lib/gcc/current/libgcc_s.1.dylib ./
# ln -s ../Cellar/gcc/14.1.0/lib/gcc/current/libgcc_s.1.1.dylib ./

cd "${TARGET}" || exit
make distclean && ./autogen.sh  && \
    # LIBRARY_PATH="$(brew --prefix gcc)/lib/gcc/current:$(brew --prefix libgccjit)/lib/gcc/current:$(brew --prefix gcc)/lib/gcc/current/gcc/x86_64-apple-darwin23/14" \
    # LDFAGS="-Wl,-rpath,$(brew --prefix gcc)/lib/gcc/current,$(brew --prefix libgccjit)/lib/gcc/current,$(brew --prefix gcc)/lib/gcc/current/gcc/x86_64-apple-darwin23/14" \
    CFLAGS=$(xml2-config --cflags) \
    ./configure $NATIVE_COMP "${DO_CONFIGURE_OPTS[@]}" && \
    make V=0 -j "${DO_CORES}" && make install && (
        test -d "${APPS}" && rm -fr "${APPS}"
        open -R nextstep/Emacs.app
    )
#    LIBRARY_PATH="$(brew --prefix gcc)/lib/gcc/current:$(brew --prefix libgccjit)/lib/gcc/current:$(brew --prefix gcc)/lib/gcc/current/gcc/x86_64-apple-darwin23/14" \
#    LDFAGS="-Wl,-rpath,$(brew --prefix gcc)/lib/gcc/current,$(brew --prefix libgccjit)/lib/gcc/current,$(brew --prefix gcc)/lib/gcc/current/gcc/x86_64-apple-darwin23/14" \
