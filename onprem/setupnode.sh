#!/bin/bash
# from http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -e
set -u
set -o pipefail

#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/setupnode.sh | bash
#
#

version="2018.04.16.03"
echo "---- setupnode version $version ----"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# logging based on https://github.com/fredpalmer/log4bash
curl -sSL -o ./log4bash.sh "$GITHUB_URL/common/log4bash.sh?p=$RANDOM"
source ./log4bash.sh

curl -sSL -o ./common.sh "$GITHUB_URL/common/common.sh?p=$RANDOM"
source ./common.sh

createShortcutFordos $GITHUB_URL

SetupNewNode $GITHUB_URL

SetupNewWorkerNode $GITHUB_URL

echo "---- finish setupnode version $version ----"