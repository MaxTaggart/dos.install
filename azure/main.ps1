param([bool]$prerelease, [bool]$local)    
$version = "2018.05.31.01"
Write-Host "--- main.ps1 version $version ---"
Write-Host "prerelease flag: $prerelease"

# http://www.rlmueller.net/PSGotchas.htm
# Trap {"Error: $_"; Break;}
# Set-StrictMode -Version latest

if ($local) {
    Write-Host "use local files: $local"    
}

# https://stackoverflow.com/questions/9948517/how-to-stop-a-powershell-script-on-the-first-error
# Set-StrictMode -Version latest

# stop whenever there is an error
$ErrorActionPreference = "Stop"
# show Information messages
$InformationPreference = "Continue"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1 | iex;
#   curl -sSL  https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1 | pwsh -Interactive -NoExit -c -;

if ($prerelease) {
    if($local){
        #$GITHUB_URL = "."
        $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
    }
    else {
        $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
    }
}
else {
    $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/release"
}
Write-Host "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Host "Powershell version: $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Build)"

if ($local) {
    Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;
}
else {
    Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring | Invoke-Expression;    
}

if ($local) {
    Get-Content ./common/common.ps1 -Raw | Invoke-Expression;
}
else {
    Invoke-WebRequest -useb ${GITHUB_URL}/common/common.ps1?f=$randomstring | Invoke-Expression;    
}

if ($local) {
    Get-Content ./common/common-azure.ps1 -Raw | Invoke-Expression;
}
else {
    Invoke-WebRequest -useb ${GITHUB_URL}/common/common-azure.ps1?f=$randomstring | Invoke-Expression;    
}

if ($local) {
    Get-Content ./common/product-menu.ps1 -Raw | Invoke-Expression;
}
else {
    Invoke-WebRequest -useb ${GITHUB_URL}/common/product-menu.ps1?f=$randomstring | Invoke-Expression;    
}

if ($local) {
    Get-Content ./common/troubleshooting-menu.ps1 -Raw | Invoke-Expression;
}
else {
    Invoke-WebRequest -useb ${GITHUB_URL}/common/troubleshooting-menu.ps1?f=$randomstring | Invoke-Expression;    
}

# if(!(Test-Path .\Fabric-Install-Utilities.psm1)){
#     Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -Headers @{"Cache-Control"="no-cache"} -OutFile Fabric-Install-Utilities.psm1
# }
# Import-Module -Name .\Fabric-Install-Utilities.psm1 -Force

$userinput = ""
while ($userinput -ne "q") {
    $skip = $false
    $currentcluster = ""
    if (Test-CommandExists kubectl) {
        $currentcluster = $(kubectl config current-context 2> $null)
    }
    
    Write-Host "================ Health Catalyst version $version, common: $(GetCommonVersion) azure: $(GetCommonAzureVersion) kube: $(GetCommonKubeVersion) ================"
    if ($prerelease) {
        Write-Host "prerelease flag: $prerelease"
    }
    Write-Warning "CURRENT CLUSTER: $currentcluster"    
    Write-Host "0: Change kube to point to another cluster"
    Write-Host "------ Infrastructure -------"
    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Configure existing Azure Container Service"
    Write-Host "3: Start VMs in Resource Group"
    Write-Host "4: Stop VMs in Resource Group"
    Write-Host "5: Renew Azure token"
    Write-Host "6: Show NameServers to add in GoDaddy"
    Write-Host "7: Setup Azure DNS entries"
    Write-Host "8: Show DNS entries to make in CAFE DNS"
    Write-Host "9: Show nodes"
    Write-Host "10: Show DNS entries for /etc/hosts"
    Write-Host "----- Troubleshooting ----"
    Write-Host "20: Show status of cluster"
    Write-Host "21: Launch Kubernetes Admin Dashboard"
    Write-Host "22: Show SSH commands to VMs"
    Write-Host "23: View status of DNS pods"
    Write-Host "24: Restart all VMs"
    Write-Host "25: Flush DNS on local machine"
    Write-Host "26: Copy Kubernetes secrets to keyvault"
    Write-Host "27: Copy secrets from keyvault to kubernetes"
    Write-Host "------ Load Balancer -------"
    Write-Host "30: Test load balancer"
    Write-Host "31: Fix load balancers"
    Write-Host "32: Redeploy load balancers"
    Write-Host "33: Launch Load Balancer Dashboard"
    Write-Host "-----------"
    Write-Host "50: Troubleshooting Menu"
    Write-Host "-----------"
    Write-Host "51: Fabric NLP Menu"
    Write-Host "-----------"
    Write-Host "52: Fabric Realtime Menu"
    Write-Host "-----------"
    Write-Host "53: Fabric MachineLearning Menu"
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
        
            CreateACSCluster -baseUrl $GITHUB_URL -config $config
            ConfigureKubernetes -config $config
            SetupAzureLoadBalancer -baseUrl $GITHUB_URL -config $config
            WriteDNSCommands
        } 
        '2' {
            $config = $(ReadConfigFile).Config
            Write-Host $config
        
            ConfigureKubernetes -config $config
            SetupAzureLoadBalancer -baseUrl $GITHUB_URL -config $config
            WriteDNSCommands
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
        '10' {
            Write-Host "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
            $loadBalancerIPResult = GetLoadBalancerIPs
            $EXTERNAL_IP = $loadBalancerIPResult.ExternalIP

            $dnshostname = $(ReadSecretValue -secretname "dnshostname" -namespace "default")
            Write-Host "$EXTERNAL_IP $dnshostname"            
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
            RestartAzureVMsInResourceGroup
        } 
        '25' {
            Read-Host "Script needs elevated privileges to flushdns.  Hit ENTER to launch script to set PATH"
            Start-Process powershell -verb RunAs -ArgumentList "ipconfig /flushdns"
        } 
        '26' {
            $DEFAULT_RESOURCE_GROUP = ReadSecretData -secretname azure-secret -valueName resourcegroup
            CopyKubernetesSecretsToKeyVault -resourceGroup $DEFAULT_RESOURCE_GROUP
        }
        '27' {
            $DEFAULT_RESOURCE_GROUP = ReadSecretData -secretname azure-secret -valueName resourcegroup
            CopyKeyVaultSecretsToKubernetes -resourceGroup $DEFAULT_RESOURCE_GROUP
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
            $config = $(ReadConfigFile).Config
            Write-Host $config
        
            SetupAzureLoadBalancer -baseUrl $GITHUB_URL -config $config -local $local
            WriteDNSCommands
        }         
        '33' {
            OpenTraefikDashboard
        } 
        '50' {
            showTroubleshootingMenu -baseUrl $GITHUB_URL -isAzure $true
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
        '53' {
            showMenu -baseUrl $GITHUB_URL -namespace "fabricmachinelearning" -isAzure $true
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
