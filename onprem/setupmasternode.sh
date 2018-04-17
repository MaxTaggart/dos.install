#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/setupmaster.txt | bash
#
#

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# logging based on https://github.com/fredpalmer/log4bash
curl -sSL -o ./log4bash.sh "$GITHUB_URL/common/log4bash.sh?p=$RANDOM"
source ./log4bash.sh

curl -sSL -o ./common.sh "$GITHUB_URL/common/common.sh?p=$RANDOM"
source ./common.sh

version="2018.04.16.01"
echo "---- setupmaster version $version ----"

SetupNewMasterNode $GITHUB_URL

echo "---- end setupmaster version $version ----"
