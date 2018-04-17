$version = "2018.04.16.04"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1 | iex;
#   curl -sSL  https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1 | pwsh -Interactive -NoExit -c -;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Host "Powershell version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Build)"

Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

# Invoke-WebRequest -useb $GITHUB_URL/common/common-onprem.ps1?f=$randomstring | Invoke-Expression;
Get-Content ./common/common-onprem.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/common/common-onprem.ps1 -Headers @{"Cache-Control"="no-cache"} -OutFile common-onprem.psm1
Import-Module -Name .\common-onprem.psm1 -Force

# show Information messages
$InformationPreference = "Continue"

$userinput = ""
while ($userinput -ne "q") {
    Write-Host "================ Health Catalyst version $version, common functions $(GetCommonVersion) $(GetCommonKubeVersion) ================"
    Write-Host "------ Infrastructure -------"
    Write-Host "1: Create Master VM"
    Write-Host "2: Create Worker VM"
    Write-Host "3: Create Single Node Cluster"
    Write-Host "-----------"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '1' {
            SetupMaster -baseUrl $GITHUB_URL -singlenode $true
        } 
        '2' {
            SetupNewNode -baseUrl $GITHUB_URL
        } 
        '3' {
            SetupMaster -baseUrl $GITHUB_URL -singlenode $false
        } 
        'q' {
            return
        }
    }
    $userinput = Read-Host -Prompt "Press Enter to continue or q to exit"
    if($userinput -eq "q"){
        return
    }
    [Console]::ResetColor()
    Clear-Host
}
