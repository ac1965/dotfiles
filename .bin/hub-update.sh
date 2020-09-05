#! /usr/bin/env bash

THIS=${T:-$HOME/devel/src}
TARGET="${THIS}/${1:-${GIT_DEFAULT_SITE}}"
LOG="${THIS}/hub-update.log"

date | tee -a $LOG
test -d $TARGET && (
    cd $TARGET
    test -f $LOG && rm -f $LOG
    for d in $(gls --color=none)
    do
        (
        cd $d
        test -x ~/.bin/hub-repos.sh && ~/.bin/hub-repos.sh $(pwd | awk -F'/' '{print $NF}') > repos-${d}.txt
        for g in $(gls --color=none -l | grep "^d" | awk '{print $NF}')
        do
            (
                echo -- https://${GIT_DEFAULT_SITE}/${d}/${g}.git
                cd $g
                git pull
            )
        done
        ) | tee -a $LOG
    done
) || echo $0 git-site
