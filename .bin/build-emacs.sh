#! /usr/bin/env bash

# Prequisites
# - Xcode
# - git
# - imagemagick (allows image viewing)
# - gnutls (allows communication via SSL, TLS, amd DTLS)
# - autoconf
# - automake


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

cd $TARGET
./autogen.sh  && \
    CFLAGS=`xml2-config --cflags` ./configure && make install && (
        test -d $APPS && rm -fr $APPS
        open -R nextstep/Emacs.app
    )
