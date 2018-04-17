#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/mountfolder.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

# logging based on https://github.com/fredpalmer/log4bash
curl -sSL -o ./log4bash.sh "$GITHUB_URL/common/log4bash.sh?p=$RANDOM"
source ./log4bash.sh

curl -sSL -o ./common.sh "$GITHUB_URL/common/common.sh?p=$RANDOM"
source ./common.sh

version="2018.04.13.01"

echo "---- mountfolder.sh version $version ------"
pathToShare=$1
username=$2
domain=$3
password=$4

mountSMBWithParams $pathToShare $username $domain $password false true

