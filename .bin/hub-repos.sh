#/usr/bin/env bash

set -o nounset
set -o noclobber

curl "https://api.github.com/users/${1:-${SNS_USERNAME}}/repos?per_page=100" 2>/dev/null | jq -r '.[].name'
