#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/setup-loadbalancer.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")
# source ./common/common.sh

version="2018.04.16.01"

echo "---- setup-loadbalancer.sh version $version ------"
SetupNewLoadBalancer $GITHUB_URL

echo "---- end of setup-loadbalancer.sh version $version ------"