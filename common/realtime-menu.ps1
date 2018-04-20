$versionmenucommon = "2018.04.18.01"

Write-Information -MessageData "Including realtime-menu.ps1 version $versionmenucommon"
function global:GetCommonMenuVersion() {
    return $versionmenucommon
}

function showRealtimeMenu([ValidateNotNullOrEmpty()][string] $baseUrl){
    $namespace="fabricrealtime"
    $userinput = ""
    while ($userinput -ne "q") {
        Write-Host "================ Health Catalyst version $version, common functions kube:$(GetCommonKubeVersion) onprem:$(GetCommonOnPremVersion) ================"
        Write-Host "------ Install -------"
        Write-Host "1: Install Realtime"
        Write-Host "------ Status --------"
        Write-Host "2: Show status of realtime"
        Write-Host "3: Show web site urls"
        Write-Host "4: Show realtime passwords"
        Write-Host "5: Show Realtime detailed status"
        Write-Host "6: Show Realtime logs"
        Write-Host "7: Show urls to download client certificates"
        Write-Host "8: Show DNS entries for /etc/hosts"
        Write-Host "9: Troubleshoot Ingresses"        
        Write-Host "-----------"
        Write-Host "q: Quit"
        $userinput = Read-Host "Please make a selection"
        switch ($userinput) {
            '1' {
                InstallStack $baseUrl "$namespace" "realtime"
            } 
            '2' {
                kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=$namespace -o wide
            } 
            '3' {
                $certhostname = $(ReadSecret certhostname $namespace)
                Write-Host "Send HL7 to Mirth: server=${certhostname} port=6661"
                Write-Host "Rabbitmq Queue: server=${certhostname} port=5671"
                Write-Host "RabbitMq Mgmt UI is at: http://${certhostname}/rabbitmq/ user: admin password: $(ReadSecretPassword rabbitmqmgmtuipassword $namespace)"
                Write-Host "Mirth Mgmt UI is at: http://${certhostname}/mirth/ user: admin password:admin"
            } 
            '4' {
                Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword $namespace)"
                Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword $namespace)"
                Write-Host "certhostname: $(ReadSecret certhostname $namespace)"
                Write-Host "certpassword: $(ReadSecretPassword certpassword $namespace)"
                Write-Host "rabbitmq mgmtui user: admin password: $(ReadSecretPassword rabbitmqmgmtuipassword $namespace)"            
            } 
            '5' {
                ShowStatusOfAllPodsInNameSpace "$namespace"
            } 
            '6' {
                ShowLogsOfAllPodsInNameSpace "$namespace"
            } 
            '7' {
                $certhostname=$(ReadSecret certhostname $namespace)
                $certpassword=$(ReadSecretPassword certpassword $namespace)
                $url="http://${certhostname}/certificates/client/fabricrabbitmquser_client_cert.p12"
                Write-Host "Download the client certificate:"
                Write-Host "$url"
                Write-Host "Double-click and install in Local Machine. password: $certpassword"
                Write-Host "Open Certificate Management, right click on cert and give everyone access to key"
                
                $url="http://${certhostname}/certificates/client/fabric_ca_cert.p12"
                Write-Host "Optional: Download the CA certificate:"
                Write-Host "$url"
                Write-Host "Double-click and install in Local Machine. password: $certpassword"            
            } 
            '8' {
                Write-Host "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
                $loadBalancerIP=$(dig +short myip.opendns.com "@resolver1.opendns.com")
                $certhostname=$(ReadSecret certhostname $namespace)
                Write-Host "$loadBalancerIP $certhostname"            
            } 
            '9' {
                troubleshootIngress "$namespace"
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

Write-Information -MessageData "end realtime-menu.ps1 version $versionmenucommon"