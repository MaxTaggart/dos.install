param([bool]$prerelease)    
$version = "2018.05.01.03"
Write-Host "--- main.ps1 version $version ---"
Write-Host "prerelease flag: $prerelease"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1 | iex;
#   curl -sSL  https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1 | pwsh -Interactive -NoExit -c -;

if ($prerelease) {
    $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
}
else {
    $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/release"
}
Write-Host "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Host "Powershell version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Build)"

Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common-azure.ps1 | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/product-menu.ps1?f=$randomstring | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/troubleshooting-menu.ps1?f=$randomstring | Invoke-Expression;

# if(!(Test-Path .\Fabric-Install-Utilities.psm1)){
#     Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -Headers @{"Cache-Control"="no-cache"} -OutFile Fabric-Install-Utilities.psm1
# }
# Import-Module -Name .\Fabric-Install-Utilities.psm1 -Force

# show Information messages
$InformationPreference = "Continue"

$userinput = ""
while ($userinput -ne "q") {
    $skip = $false
    $currentcluster = ""
    if (Test-CommandExists kubectl) {
        $currentcluster = $(kubectl config current-context 2> $null)
    }
    
    Write-Host "================ Health Catalyst version $version, common functions $(GetCommonVersion) $(GetCommonKubeVersion) ================"
    if ($prerelease) {
        Write-Host "prerelease flag: $prerelease"
    }
    Write-Host "0: Change kube to point to another cluster"
    Write-Host "------ Infrastructure -------"
    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Setup Load Balancer"
    Write-Host "3: Start VMs in Resource Group"
    Write-Host "4: Stop VMs in Resource Group"
    Write-Host "5: Renew Azure token"
    Write-Host "6: Show NameServers to add in GoDaddy"
    Write-Host "7: Setup Azure DNS entries"
    Write-Host "8: Show DNS entries to make in CAFE DNS"
    Write-Host "9: Show nodes"
    Write-Host "------ Install -------"
    Write-Host "11: Install NLP"
    Write-Host "12: Install Realtime"
    Write-Host "----- Troubleshooting ----"
    Write-Host "20: Show status of cluster"
    Write-Host "21: Launch Kubernetes Admin Dashboard"
    Write-Host "22: Show SSH commands to VMs"
    Write-Host "23: View status of DNS pods"
    Write-Host "24: Restart all VMs"
    Write-Host "25: Flush DNS on local machine"
    Write-Host "------ Load Balancer -------"
    Write-Host "30: Test load balancer"
    Write-Host "31: Fix load balancers"
    Write-Host "32: Show load balancer logs"
    Write-Host "33: Launch Load Balancer Dashboard"
    Write-Host "-----------"
    Write-Host "50: Troubleshooting Menu"
    Write-Host "-----------"
    Write-Host "51: Fabric NLP Menu"
    Write-Host "-----------"
    Write-Host "52: Fabric Realtime Menu"
    Write-Host "-----------"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '0' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            $folders = Get-ChildItem "C:\kubernetes" -directory
            for ($i = 1; $i -le $folders.count; $i++) {
                Write-Host "$i. $($folders[$i-1])"
            }              
            $index = Read-Host "Enter number of folder to use (1 - $($folders.count))"
            $folderToUse = $($folders[$index - 1])

            SwitchToKubCluster -folderToUse "C:\kubernetes\$folderToUse"
        } 
        '1' {
            $config = $(ReadConfigFile).Config
            Write-Host $config
        
            CreateACSCluster
            SetupAzureLoadBalancer
        } 
        '2' {
            $config = $(ReadConfigFile).Config
            Write-Host $config
        
            SetupAzureLoadBalancer
        } 
        '3' {
            Do { 
                $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group"
            }
            while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))

            StartVMsInResourceGroup -resourceGroup $AKS_PERS_RESOURCE_GROUP 
        } 
        '4' {
            Do { 
                $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group"
            }
            while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
            StopVMsInResourceGroup -resourceGroup $AKS_PERS_RESOURCE_GROUP 
        } 
        '5' {
            $expiresOn = $(az account get-access-token --query "expiresOn" -o tsv)
            Do { $confirmation = Read-Host "Your current access token expires on $expiresOn. Do you want to login again to get a new access token? (y/n)"}
            while ([string]::IsNullOrWhiteSpace($confirmation))
        
            if ($confirmation -eq "y") {
                RenewAzureToken
            }
        }         
        '6' {
            $DNS_RESOURCE_GROUP = Read-Host "Resource group containing DNS zones? (default: dns)"
            if ([string]::IsNullOrWhiteSpace($DNS_RESOURCE_GROUP)) {
                $DNS_RESOURCE_GROUP = "dns"
            }

            $customerid = ReadSecretValue -secretname customerid
            $customerid = $customerid.ToLower().Trim()

            $dnsrecordname = "$customerid.healthcatalyst.net"
                    
            ShowNameServerEntries -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname
        } 
        '7' {
            $DNS_RESOURCE_GROUP = Read-Host "Resource group containing DNS zones? (default: dns)"
            if ([string]::IsNullOrWhiteSpace($DNS_RESOURCE_GROUP)) {
                $DNS_RESOURCE_GROUP = "dns"
            }

            $customerid = ReadSecretValue -secretname customerid
            $customerid = $customerid.ToLower().Trim()

            $dnsrecordname = "$customerid.healthcatalyst.net"

            $loadBalancerIPResult = GetLoadBalancerIPs
            $EXTERNAL_IP = $loadBalancerIPResult.ExternalIP

            SetupDNS -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname -externalIP $EXTERNAL_IP 
        }
        '8' {
            WriteDNSCommands
        } 
        '9' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl version --short
            kubectl get "nodes"
        } 
        '11' {
            # $namespace="fabricnlp"
            # CreateNamespaceIfNotExists $namespace
            # AskForPasswordAnyCharacters -secretname "smtprelaypassword" -prompt "Please enter SMTP relay password" -namespace $namespace
            # $dnshostname=$(ReadSecretValue -secretname "dnshostname" -namespace "default")
            # SaveSecretValue -secretname "nlpweb-external-url" -valueName "url" -value "nlp.$dnshostname" -namespace $namespace
            # SaveSecretValue -secretname "jobserver-external-url" -valueName "url" -value "nlpjobs.$dnshostname" -namespace $namespace
            InstallStack -namespace $namespace -baseUrl $GITHUB_URL -appfolder "nlp" -isAzure 1
        } 
        '12' {
            # CreateNamespaceIfNotExists "fabricrealtime"
            InstallStack -namespace "fabricrealtime" -baseUrl $GITHUB_URL -appfolder "realtime" -isAzure 1
        } 
        '20' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl version --short
            kubectl get "deployments,pods,services,ingress,secrets,nodes" --namespace=kube-system -o wide
        } 
        '21' {
            LaunchAzureKubernetesDashboard
        } 
        '22' {        
            ShowSSHCommandsToVMs
        } 
        '23' {
            RestartDNSPodsIfNeeded
        } 
        '24' {
            RestartVMsInResourceGroup
        } 
        '25' {
            Read-Host "Script needs elevated privileges to flushdns.  Hit ENTER to launch script to set PATH"
            Start-Process powershell -verb RunAs -ArgumentList "ipconfig /flushdns"
        } 
        '30' {
            TestAzureLoadBalancer
        } 
        '31' {
            $DEFAULT_RESOURCE_GROUP = ReadSecretData -secretname azure-secret -valueName resourcegroup
            
            if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
                Do { 
                    $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group: (default: $DEFAULT_RESOURCE_GROUP)"
                    if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
                        $AKS_PERS_RESOURCE_GROUP = $DEFAULT_RESOURCE_GROUP
                    }
                }
                while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
            }
            FixLoadBalancers -resourceGroup $AKS_PERS_RESOURCE_GROUP
        } 
        '32' {
            $pods = $(kubectl get pods -l k8s-traefik=traefik -n kube-system -o jsonpath='{.items[*].metadata.name}')
            foreach ($pod in $pods.Split(" ")) {
                Write-Host "=============== Pod: $pod ================="
                kubectl logs --tail=20 $pod -n kube-system 
            }
        }         
        '33' {
            LaunchAzureLoadBalancerDashboard
        } 
        '50' {
            showTroubleshootingMenu -baseUrl $baseUrl -isAzure $true
            $skip = $true
        }                 
        '51' {
            showMenu -baseUrl $GITHUB_URL -namespace "fabricnlp" -isAzure $true
            $skip = $true
        } 
        '52' {
            showMenu -baseUrl $GITHUB_URL -namespace "fabricrealtime" -isAzure $true
            $skip = $true
        } 
        'q' {
            return
        }
    }
    if (!($skip)) {
        $userinput = Read-Host -Prompt "Press Enter to continue or q to exit"
        if ($userinput -eq "q") {
            return
        }    
    }
    [Console]::ResetColor()
    Clear-Host
}
