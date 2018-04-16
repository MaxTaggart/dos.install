#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/setupmaster.txt | bash
#
#

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
source <(curl -sSL "$GITHUB_URL/common/common.sh")

version="2018.04.16.01"
echo "---- setupmaster version $version ----"

SetupNewMasterNode $GITHUB_URL

echo "---- end setupmaster version $version ----"
