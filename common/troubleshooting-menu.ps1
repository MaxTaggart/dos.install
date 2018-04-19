$versionmenutroubleshooting = "2018.04.18.01"

Write-Information -MessageData "Including troubleshooting-menu.ps1 version $versionmenucommon"
function global:GetTroubleshootingMenuVersion() {
    return $versionmenutroubleshooting
}

function showTroubleshootingMenu([ValidateNotNullOrEmpty()][string] $baseUrl){
    $userinput = ""
    while ($userinput -ne "q") {
        Write-Host "================ Health Catalyst version $version, common functions kube:$(GetCommonKubeVersion) onprem:$(GetCommonOnPremVersion) ================"
        Write-Host "1: Optimize Centos under Hyper-V"
        Write-Host "2: Show load balancer logs"
        Write-Host "3: Troubleshoot networking"
        Write-Host "4: Test DNS"
        Write-Host "5: Show contents of shared folder"
        Write-Host "6: Show dashboard url"
        Write-Host "7: Show kubernetes service status"
        Write-Host "-----------"
        Write-Host "11: Reinstall Load Balancer"
        Write-Host "12: Reinstall Kubernetes Dashboard"
        Write-Host "q: Quit"
        $userinput = Read-Host "Please make a selection"
        switch ($userinput) {
            '1' {
                OptimizeCentosForHyperv
            } 
            '2' {
                ShowLoadBalancerLogs
            } 
            '3' {
                TroubleshootNetworking
            } 
            '4' {
                TestDNS $baseUrl
            } 
            '5' {
                ShowContentsOfSharedFolder
            } 
            '6' {
                OpenKubernetesDashboard
            } 
            '7' {
                ShowKubernetesServiceStatus
            } 
            '11' {
                SetupNewLoadBalancer $baseUrl
            } 
            '12' {
                InstallStack $baseUrl "kube-system" "dashboard"
            } 
            'q' {
                return
            }
        }
        $userinput = Read-Host -Prompt "Press Enter to continue or q to exit"
        if ($userinput -eq "q") {
            return
        }
        [Console]::ResetColor()
        Clear-Host
    }        
}

Write-Information -MessageData "end realtime-menu.ps1 version $versionmenutroubleshooting"