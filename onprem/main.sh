#!/bin/bash
# from http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -e
set -u
set -o pipefail
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/release/onprem/main.sh -o main.sh; bash main.sh
#   To test with the latest code on the master
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/main.sh -o main.sh; bash main.sh -prerelease
#   obsolete:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/main.sh | bash
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/main.sh -o "${HOME}/main.sh"; bash "${HOME}/main.sh"
#   curl https://bit.ly/2GOPcyX | bash
#
version="2018.04.23.01"

prerelease=false
if [[ "${1:-}" = "-prerelease" ]]; then
    prerelease=true
fi

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/release"
if [[ "${prerelease:-false}" = true ]]; then
    GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
    echo "-prerelease flag passed so switched GITHUB_URL to $GITHUB_URL"
fi

if [ ! -x "$(command -v yum)" ]; then
    echo "ERROR: yum command is not available"
    exit
fi

echo "CentOS version: $(cat /etc/redhat-release | grep -o '[0-9]\.[0-9]')"
echo "$(cat /etc/redhat-release)"

if [[ "$TERM" = "cygwin" ]]; then
    echo "Your TERM is set to cygwin.  We do not support this because it has issues in displaying text.  Please use a different SSH terminal e.g., MobaXterm"
    exit 1
fi

curl -sSL -o ./common.sh "$GITHUB_URL/common/common.sh?p=$RANDOM"
source ./common.sh

# source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")
# source ./common/common.sh

# this sets the keyboard so it handles backspace properly
# http://www.peachpit.com/articles/article.aspx?p=659655&seqNum=13
echo "running stty sane to fix terminal keyboard mappings"
stty sane < /dev/tty

# echo "setting TERM to xterm"
# export TERM=xterm

echo "--- creating shortcut for dos ---"
createShortcutFordos $GITHUB_URL $prerelease

echo "--- installing prerequisites ---"
InstallPrerequisites

dos

echo " --- end of main.sh $version ---"
