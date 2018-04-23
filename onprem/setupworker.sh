#!/bin/bash
# from http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -e
set -u
set -o pipefail

#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/setupworker.sh | bash
#
#

version="2018.04.18.02"
echo "---- setupnode version $version ----"

joincommand=$1
prerelease=false
if [[ "${2:-}" = "-prerelease" ]]; then
    prerelease=true
fi

echo "joincommand: $joincommand"
echo "prerelease: $prerelease"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/release"
if [[ "${prerelease:-false}" = true ]]; then
    GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
    echo "-prerelease flag passed so switched GITHUB_URL to $GITHUB_URL"
fi

if [[ "$TERM" = "cygwin" ]]; then
    echo "Your TERM is set to cygwin.  We do not support this because it has errors in displaying text.  Please use a different SSH terminal e.g., MobaXterm"
    exit 1
fi

# this sets the keyboard so it handles backspace properly
# http://www.peachpit.com/articles/article.aspx?p=659655&seqNum=13
echo "running stty sane to fix terminal keyboard mappings"
stty sane < /dev/tty

curl -sSL -o ./common.sh "$GITHUB_URL/common/common.sh?p=$RANDOM"
source ./common.sh

echo "--- creating shortcut for dos ---"
createShortcutFordos $GITHUB_URL

echo "--- installing prerequisites ---"
InstallPrerequisites

echo "--- download setupworker.ps1 ---"
curl -o "${HOME}/setupworker.ps1" -sSL "${GITHUB_URL}/onprem/setupworker.ps1?p=$RANDOM"

echo "--- running setupworker.ps1 ---"
pwsh -f "${HOME}/setupworker.ps1" -baseUrl $GITHUB_URL -joincommand "$joincommand"

echo "---- finish setupnode version $version ----"