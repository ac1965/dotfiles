#!/bin/zsh

# Install Homebrew
if ! command -v brew &> /dev/null; then
    # Install Command line tools
    echo "Install Command line tools..."
    xcode-select --install

    echo "Install Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# iTerm2
if [[ ! -d /Applications/iTerm.app ]]; then
    brew install --cask iterm2
fi
