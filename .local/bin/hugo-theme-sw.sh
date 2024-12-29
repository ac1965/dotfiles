#!/bin/bash

if [ $# = 0 ]; then
    echo $0 theme
    exit
fi

base="/Users/ac1965/Documents/devel/repos/hugo-blog"
target=${base}/config/${1}

test -d ${target} && (
    echo ${1} use
    cd ${base}/config
    test -d _default && rm -fr _default
    cp -a ${1} _default
    cd ${base}
    test -d public && rm -fr public
    hugo server --debug  --disableFastRender
) || echo not found ${target}
