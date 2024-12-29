#/usr/bin/env bash

set -o nounset
set -o noclobber

GITHUB_TOKEN=${GITHUB_TOKEN:-""}
GITHUB_APIURL=${GITHUB_APIURL:-"https://api.github.com"}
GITHUB_API="/users/${1:-${SNS_USERNAME}}"

curl -k -s -u :${GITHUB_TOKEN} ${GITHUB_APIURL}${GITHUB_API}/repos?per_page=100 2>/dev/null | jq -r '.[].name'
