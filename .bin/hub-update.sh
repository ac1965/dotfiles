#! /usr/bin/env bash

THIS="$HOME/Documents/devel/src"
TARGET="${THIS}/${1:-${GIT_DEFAULT_SITE}}"

test -d $TARGET && (
    cd $TARGET
    pwd
    for d in $(gls --color=none)
    do
        (
        cd $d
        for g in $(gls --color=none -l | grep "^d" | awk '{print $NF}')
        do
            (
                echo -- $d  $g
                cd $g
                pwd
                git pull
            )
        done
        )
    done
) || echo $0 git-site

