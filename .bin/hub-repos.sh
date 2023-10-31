#/usr/bin/env bash

set -o nounset
set -o noclobber

GITHUB_TOKEN=${GITHUB_TOKEN:-""}
GITHUB_APIURL="https://api.github.com"
GITHUB_API="/users/${1:-${SNS_USERNAME}}/repos?per_page=100"

curl -k -s -u :${GITHUB_TOKEN} ${GITHUB_APIURL}${GITHUB_API} 2>/dev/null | jq -r '.[].name'
