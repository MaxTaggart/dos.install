$version = "2018.04.17.02"

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
    Write-Host "7: Launch Kubernetes dashboard"
    Write-Host "-----------"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '1' {
            SetupMaster -baseUrl $GITHUB_URL -singlenode $false
        } 
        '2' {
            SetupNewNode -baseUrl $GITHUB_URL
        } 
        '3' {
            SetupMaster -baseUrl $GITHUB_URL -singlenode $true
        } 
        '4' {
            UninstallDockerAndKubernetes
        } 
        '5' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl version --short
            kubectl get "nodes" -o wide
        } 
        '6' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl version --short
            kubectl get "deployments,pods,services,nodes,ingress" --namespace=kube-system -o wide
        } 
        '7' {
            $dnshostname=$(ReadSecret "dnshostname")
            $myip=$(host $(hostname) | awk '/has address/ { print $4 ; exit }')
            Write-Host "--- dns entries for c:\windows\system32\drivers\etc\hosts (if needed) ---"
            Write-Host "${myip} ${dnshostname}"
            Write-Host "-----------------------------------------"
            Write-Host "You can access the kubernetes dashboard at: https://${dnshostname}/api/ or https://${myip}/api/"
            $secretname=$(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
            $token=$(ReadSecretValue "$secretname" "token" "kube-system")
            Write-Host "----------- Bearer Token ---------------"
            Write-Host $token
            Write-Host "-------- End of Bearer Token -------------"
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
