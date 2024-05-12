brew uninstall \
    --ignore-dependencies \
    libgccjit \
    gcc \
    emacs-plus
brew install \
    --ignore-dependencies \
    --build-from-source \
    libgccjit \
    gcc
cd "$(brew --prefix)/lib"
ln -s ../Cellar/libgccjit/12.2.0/lib/gcc/12/libgccjit.dylib ./
ln -s ../Cellar/libgccjit/12.2.0/lib/gcc/12/libgccjit.0.dylib ./
cd -
LIBRARY_PATH="$(brew --prefix)/lib" \
    HOMEBREW_NO_INSTALL_CLEANUP=1 \
    brew install \
    --ignore-dependencies \
    emacs-plus@29 \
    --with-native-comp \
    --with-xwidgets \
    --with-imagemagick \
    --with-mailutils \
    --with-poll \
    --with-no-frame-refocus \
    --with-spacemacs-icon
