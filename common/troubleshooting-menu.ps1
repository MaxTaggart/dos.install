$versionmenutroubleshooting = "2018.06.05.01"

Write-Information -MessageData "Including troubleshooting-menu.ps1 version $versionmenucommon"
function global:GetTroubleshootingMenuVersion() {
    return $versionmenutroubleshooting
}

function showTroubleshootingMenu([ValidateNotNullOrEmpty()][string] $baseUrl, [bool]$isAzure) {
    $userinput = ""
    while ($userinput -ne "q") {
        Write-Host "================ Troubleshooting menu version $versionmenutroubleshooting, common functions kube:$(GetCommonKubeVersion) ================"
        Write-Host "0: Show status of cluster"        
        Write-Host "-----  Kubernetes ------"
        Write-Host "1: Open Kubernetes dashboard"
        Write-Host "2: Troubleshoot networking"
        Write-Host "3: Test DNS"
        Write-Host "4: Show contents of shared folder"
        Write-Host "5: Show kubernetes service status"
        Write-Host "6: Troubleshoot Ingresses"
        Write-Host "7: Show logs of all pods in kube-system"
        Write-Host "-----  Traefik reverse proxy ------"
        Write-Host "11: Open Traefik dashboard"
        Write-Host "12: Show load balancer logs"
        Write-Host "----- Reinstall ------"
        Write-Host "13: Reinstall Load Balancer"
        Write-Host "14: Reinstall Traefik Dashboard"
        Write-Host "------ Other tasks ---- "
        Write-Host "31: Create a Single Node Cluster"
        Write-Host "32: Mount folder"
        Write-Host "33: Create kubeconfig"
        Write-Host "34: Move TCP ports to main LoadBalancer"
        Write-Host "--- helpers ---"
        Write-Host "41: Optimize Centos under Hyper-V"
        Write-Host "q: Go back to main menu"
        $userinput = Read-Host "Please make a selection"
        switch ($userinput) {
            '0' {
                ShowStatusOfCluster
            }                 
            '1' {
                if ($isAzure) {
                    LaunchAzureKubernetesDashboard
                }
                else {
                    OpenKubernetesDashboard
                }
            } 
            '2' {
                TroubleshootNetworking
            } 
            '3' {
                TestDNS $baseUrl
            } 
            '4' {
                ShowContentsOfSharedFolder
            } 
            '5' {
                ShowKubernetesServiceStatus
            } 
            '6' {
                troubleshootIngress "kube-system"
            } 
            '7' {
                ShowLogsOfAllPodsInNameSpace "kube-system"
            }            
            '11' {
                OpenTraefikDashboard
            } 
            '12' {
                ShowLoadBalancerLogs
            } 
            '13' {
                SetupNewLoadBalancer $baseUrl
            } 
            '14' {
                InstallStack $baseUrl "kube-system" "dashboard"
            } 
            '31' {
                SetupMaster -baseUrl $baseUrl -singlenode $true 
            } 
            '32' {
                mountSharedFolder -saveIntoSecret $true
            } 
            '33' {
                GenerateKubeConfigFile
            } 
            '34' {
                MovePortsToLoadBalancer -resourceGroup $(GetResourceGroup).ResourceGroup
            } 
            '41' {
                OptimizeCentosForHyperv
            } 
            'q' {
                return
            }
        }
        $userinput = Read-Host -Prompt "Press Enter to continue or q to go back to top menu"
        if ($userinput -eq "q") {
            return
        }
        [Console]::ResetColor()
        Clear-Host
    }        
}

Write-Information -MessageData "end troubleshooting-menu.ps1 version $versionmenutroubleshooting"