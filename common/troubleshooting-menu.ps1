$versionmenutroubleshooting = "2018.04.18.01"

Write-Information -MessageData "Including troubleshooting-menu.ps1 version $versionmenucommon"
function global:GetTroubleshootingMenuVersion() {
    return $versionmenutroubleshooting
}

function showTroubleshootingMenu([ValidateNotNullOrEmpty()][string] $baseUrl){
    $userinput = ""
    while ($userinput -ne "q") {
        Write-Host "================ Health Catalyst version $version, common functions kube:$(GetCommonKubeVersion) onprem:$(GetCommonOnPremVersion) ================"
        Write-Host "-----  Kubernetes ------"
        Write-Host "1: Open Kubernetes dashboard"
        Write-Host "2: Troubleshoot networking"
        Write-Host "3: Test DNS"
        Write-Host "4: Show contents of shared folder"
        Write-Host "5: Show kubernetes service status"
        Write-Host "6: Troubleshoot Ingresses"
        Write-Host "-----  Traefik reverse proxy ------"
        Write-Host "11: Open Traefik dashboard"
        Write-Host "12: Show load balancer logs"
        Write-Host "13: Reinstall Load Balancer"
        Write-Host "14: Reinstall Traefik Dashboard"
        Write-Host "--- helpers ---"
        Write-Host "21: Optimize Centos under Hyper-V"
        Write-Host "q: Quit"
        $userinput = Read-Host "Please make a selection"
        switch ($userinput) {
            '1' {
                OpenKubernetesDashboard
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
            '21' {
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

Write-Information -MessageData "end realtime-menu.ps1 version $versionmenutroubleshooting"