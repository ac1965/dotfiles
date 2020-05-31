#! /usr/bin/env bash

T="${HOME}/Documents/devel/src"

if [ $# -eq 1 ]; then
    url=$1
    git=$(echo $url|sed 's#http.*://##g')
    host=$(echo $git| awk -F'/' '{print $1}')
    owner=$(echo $git| awk -F'/' '{print $2}')
    repos=$(echo $git| awk -F'/' '{print $3}')
    #echo "url:$url, owner=$owner, repos=$repos"
    test -d ${T}/${host} || install -d ${T}/${host}
    test -d ${T}/${host}/${owner} || install -d ${T}/${host}/${owner}
    test -x ~/.bin/hub-repos.sh && ~/.bin/hub-repos.sh $owner > ${T}/${host}/${owner}/repos-${owner}.txt
    (
        cd ${T}/${host}/${owner}
        if [ -d ${repos} ]; then
            cd ${repos} && git pull
        else
            git clone --recursive ${url}
        fi
    )
else
    echo $0 url
    exit
fi
