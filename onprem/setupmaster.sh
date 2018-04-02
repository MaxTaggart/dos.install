#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/setupmaster.sh | bash
#
#
version="2018.04.02.06"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

if [ ! -x "$(command -v yum)" ]; then
    echo "yum command is not available"
    exit
fi

echo "CentOS version: $(cat /etc/redhat-release | grep -o '[0-9]\.[0-9]')"
echo "$(cat /etc/redhat-release)"

source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")

SetupMaster $GITHUB_URL
