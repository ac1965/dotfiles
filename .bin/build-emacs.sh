#! /usr/bin/env bash

# Prequisites
# - Xcode
# - git
# - imagemagick (allows image viewing)
# - gnutls (allows communication via SSL, TLS, amd DTLS)
# - autoconf
# - automake

DO_BREW_PACKAGES=(
    # Build dependencies
    autoconf
    cairo
    cmake
    #gcc
    libgccjit
    gnupg
    gnutls
    imagemagick
    # The macOS build uses the Cocoa image library
    #jansson
    #librsvg
    #libvterm
    libxml2
    pkg-config

    # Runtime dependencies
    texinfo
    ripgrep
    fd
    node
    python
    shfmt
)

DO_BREW_CASKS=(
    basictex
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

TARGET="${GITHUB_REPOS}/emacs-mirror/emacs"

test -x ~/.bin/hub-clone.sh || exit 9

if [ -d $TARGET ]; then
    cd $TARGET
    git reset --hard
    git clean -xdf
    git pull
else
    ~/.bin/hub-clone.sh https://github.com/emacs-mirror/emacs.git
fi

DO_CORES=$((2 * $(do_how_many_cores)))
do_brew_ensure --formula "${DO_BREW_PACKAGES[@]}"
do_brew_ensure --cask "${DO_BREW_CASKS[@]}"

cd $TARGET
./autogen.sh  && \
    CFLAGS=`xml2-config --cflags` ./configure && make -j $DO_CORES && make install && (
        test -d $APPS && rm -fr $APPS
        open -R nextstep/Emacs.app
    )
