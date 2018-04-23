param([ValidateNotNullOrEmpty()][string]$baseUrl, [string]$prerelease)    
Write-Host "--- master.ps1 version $version ---"
$version = "2018.04.18.01"
Write-Host "baseUrl = $baseUrl"
Write-Host "prerelease flag: $prerelease"

if("$prerelease" -eq "yes"){
    $isPrerelease = $true
    Write-Host "prerelease: yes"
}
else{
    $isPrerelease = $false
}

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Host "Powershell version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Build)"

mkdir -p ${HOME}

function ImportModuleFromUrl($module){
    Invoke-WebRequest -useb -Uri "${baseUrl}/common/${module}.ps1?f=$randomstring" -OutFile "${HOME}/${module}.psm1"
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
    Write-Host "1: Setup Master VM"
    Write-Host "2: Show command to join another node to this cluster"
    Write-Host "3: Uninstall Docker and Kubernetes"
    Write-Host "4: Show all nodes"
    Write-Host "5: Show status of cluster"
    Write-Host "-----------"
    Write-Host "20: Troubleshooting Menu"
    Write-Host "-----------"
    Write-Host "40: Fabric Realtime Menu"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '1' {
            SetupMaster -baseUrl $baseUrl -singlenode $false 
        } 
        '2' {
            ShowCommandToJoinCluster -baseUrl $baseUrl -prerelease $isPrerelease
        } 
        '3' {
            UninstallDockerAndKubernetes
        } 
        '4' {
            ShowNodes
        } 
        '5' {
            ShowStatusOfCluster
        } 
        '20' {
            showTroubleshootingMenu -baseUrl $baseUrl
        } 
        '40' {
            showRealtimeMenu -baseUrl $baseUrl
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
