param([string]$baseUrl,[string] $token, [string] $masterurl, [string] $discoverytoken)
# the above MUST be the first line
Write-Output "setupworker.ps1 version 2018.04.17.01"
Write-Output "Received parameters:"
Write-Output "baseUrl:$baseUrl"
Write-Output "token:$token"
Write-Output "masterurl:$masterurl"
Write-Output "discoverytoken:$discoverytoken"
Write-Output "----"

# This script is meant for quick & easy install via:
#   Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/menus/master.ps1 | iex;
#   curl -sSL  https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/menus/master.ps1 | pwsh -Interactive -NoExit -c -;

Write-Host "--- master.ps1 version $version ---"

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Host "Powershell version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Build)"

mkdir -p ${HOME}

function ImportModuleFromUrl($module){
    Invoke-WebRequest -useb -Uri "${GITHUB_URL}/common/${module}.ps1?f=$randomstring" -OutFile "${HOME}/${module}.psm1"
    Import-Module -Name "${HOME}/${module}.psm1" -Force
}

ImportModuleFromUrl -module "common"

ImportModuleFromUrl -module "common-kube"

ImportModuleFromUrl -module "common-onprem"

# show Information messages
$InformationPreference = "Continue"

SetupWorker -baseUrl $GITHUB_URL -token $token -masterurl $masterurl -discoverytoken $discoverytoken
