#! /usr/bin/env bash

T=${T:-${GITHUB_REPOS}}

if [ $# -eq 1 ]; then
    url=$1
    git=$(echo $url|sed 's#http.*://##g')
    host=$(echo $git| awk -F'/' '{print $1}')
    owner=$(echo $git| awk -F'/' '{print $2}')
    repos=$(echo $git| awk -F'/' '{print $3}')
    echo "url:$url, owner=$owner, repos=$repos"
    test -d ${T}/${host}/${owner} || install -d ${T}/${host}/${owner}
    test -x ~/.bin/hub-repos.sh && ~/.bin/hub-repos.sh $owner > ${T}/${host}/${owner}/repos-${owner}.txt
    if [ "${repos}" != "" ]; then
        (
            cd ${T}/${host}/${owner}
            if [ -d ${repos} ]; then
                cd ${repos} && git pull
            else
                git clone --recursive ${url}
            fi
        )
    fi
else
    echo $0 url
    exit
fi
