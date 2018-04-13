#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/mountfolder.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")
# source ./common/common.sh

version="2018.04.13.01"

echo "---- mountfolder.sh version $version ------"
pathToShare=$1
username=$2
domain=$3
password=$4

mountSMBWithParams $pathToShare $username $domain $password false true

