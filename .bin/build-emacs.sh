#! /usr/bin/env bash

# Prequisites
# - Xcode
# - git
# - imagemagick (allows image viewing)
# - gnutls (allows communication via SSL, TLS, amd DTLS)
# - autoconf
# - automake
# $ ./autogen.sh && \
# ./configure --with-native-compilation=aot --without-ns --without-x --with-libxml2=/usr/bin/xml2-config && make -j8

DO_BREW_PACKAGES=(
    # Build dependencies
    # brew install pkg-config automake texinfo jpeg giflib \
    #  libtiff jansson libpng librsvg gnutls cmake
    #@ cairo
    #@imagemagick
    autoconf
    cmake
    gcc
    giflib
    gnupg
    gnutls
    jansson
    libgccjit
    libtiff
    librsvg
    libxml2
    pkg-config

    # Runtime dependencies
    texinfo
    ripgrep
    fd
    node
    python
    shfmt
    mupdf
#    mupdf-tools
)

DO_BREW_CASKS=(
    mactex-no-gui
)

# ./configure --disable-dependency-tracking --disable-silent-rules  \
#            --enable-locallisppath=/opt/homebrew/share/emacs/site-lisp  \
#            --infodir=/opt/homebrew/Cellar/emacs-plus@29/29.2/share/info/emacs \
#            --prefix=/opt/homebrew/Cellar/emacs-plus@29/29.2 \
#            --with-xml2 --with-gnutls --with-native-compilation --without-compress-install \
#            --without-dbus --without-imagemagick --with-modules --with-rsvg --without-pop \
#            --with-ns --disable-ns-self-contained
DO_CONFIGURE_OPTS=(
#    --with-native-compilation=aot
    --disable-dependency-tracking
    --disable-silent-rule
    --without-compress-install
    --without-dbus
    --without-imagemagick
    --without-pop
#    --without-x
#    --with-cairo
    --with-gnutls=ifavailable
    --with-json
    --with-modules
    --with-native-compilation=yes
#    --with-native-compilation=no
    --with-rsvg
    --with-ns
    --with-tree-sitter=ifavailable
    --with-xml2
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
test -x ~/.bin/hub-clone.sh || exit 9
if [ -d "${TARGET}" ]; then
    cd "${TARGET}" || exit
    git reset --hard
    git clean -xdf
    git pull
else
    ~/.bin/hub-clone.sh "${SRC_REPOS}" # https://github.com/emacs-mirror/emacs.git
fi

DO_CORES=$((2 * $(do_how_many_cores)))
do_brew_ensure --formula "${DO_BREW_PACKAGES[@]}"
do_brew_ensure --cask "${DO_BREW_CASKS[@]}"

cd "${TARGET}" || exit
make distclean && ./autogen.sh  && \
    CFLAGS=$(xml2-config --cflags) ./configure "${DO_CONFIGURE_OPTS[@]}" && \
    make V=0 -j "${DO_CORES}" && make install && (
        test -d "${APPS}" && rm -fr "${APPS}"
        open -R nextstep/Emacs.app
    )
