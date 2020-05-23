#! /usr/bin/env bash

# Prequisites
# - Xcode
# - git
# - imagemagick (allows image viewing)
# - gnutls (allows communication via SSL, TLS, amd DTLS)
# - autoconf
# - automake

DEST="$HOME/Documents/devel/src/github.com/emacs-mirror/emacs"
APPS="/Applications/Emacs.app"

test -x ~/.bin/hub-clone.sh || exit 9

if [ -d $DEST ]; then
    cd $DEST
    git reset --hard
    git clean -xdf
    git pull
else
    ~/.bin/hub-clone.sh https://github.com/emacs-mirror/emacs.git
fi

cd $DEST
./autogen.sh  && \
    CFLAGS=`xml2-config --cflags` ./configure && make install && (
        test -d $APPS && rm -fr $APPS
        open -R nextstep/Emacs.app
    )
