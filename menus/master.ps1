$version = "2018.04.18.01"

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

ImportModuleFromUrl -module "realtime-menu"

ImportModuleFromUrl -module "troubleshooting-menu"

# show Information messages
$InformationPreference = "Continue"

$userinput = ""
while ($userinput -ne "q") {
    Write-Host "================ Health Catalyst version $version, common functions kube:$(GetCommonKubeVersion) onprem:$(GetCommonOnPremVersion) ================"
    Write-Host "------ On-Premise -------"
    Write-Host "1: Create Master VM"
    Write-Host "2: Create Worker VM"
    Write-Host "3: Create a Single Node Cluster"
    Write-Host "4: Uninstall Docker and Kubernetes"
    Write-Host "5: Show all nodes"
    Write-Host "6: Show status of cluster"
    Write-Host "8: Show command to join another node to this cluster"
    Write-Host "9: Mount folder"
    Write-Host "-----------"
    Write-Host "20: Troubleshooting Menu"
    Write-Host "-----------"
    Write-Host "40: Fabric Realtime Menu"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '1' {
            SetupMaster -baseUrl $GITHUB_URL -singlenode $false > $null
        } 
        '2' {
            SetupNewNode -baseUrl $GITHUB_URL > $null
        } 
        '3' {
            SetupMaster -baseUrl $GITHUB_URL -singlenode $true > $null
        } 
        '4' {
            UninstallDockerAndKubernetes > $null
        } 
        '5' {
            ShowNodes
        } 
        '6' {
            ShowStatusOfCluster
        } 
        '8' {
            ShowCommandToJoinCluster -baseUrl $GITHUB_URL
        } 
        '9' {
            mountSharedFolder -saveIntoSecret $true
        } 
        '20' {
            showTroubleshootingMenu -baseUrl $GITHUB_URL
        } 
        '40' {
            showRealtimeMenu -baseUrl $GITHUB_URL
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
