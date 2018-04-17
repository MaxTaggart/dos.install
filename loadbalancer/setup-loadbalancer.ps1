Write-Host "setup-loadbalancer version 2018.04.09.05"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/setup-loadbalancer.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Write-Host "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

$config = $(ReadConfigFile).Config
Write-Host $config

$AKS_IP_WHITELIST = ""

$userInfo = $(GetLoggedInUserInfo)
# $AKS_SUBSCRIPTION_ID = $userInfo.AKS_SUBSCRIPTION_ID
# $IS_CAFE_ENVIRONMENT = $userInfo.IS_CAFE_ENVIRONMENT

$AKS_PERS_RESOURCE_GROUP = $config.azure.resourceGroup
$AKS_PERS_LOCATION = $config.azure.location

# Get location name from resource group
$AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv
Write-Host "Using location: [$AKS_PERS_LOCATION]"

$customerid = $config.customerid
$customerid = $customerid.ToLower().Trim()
Write-Host "Customer ID: $customerid"

$ingressExternal = $config.ingress.external
$ingressInternal = $config.ingress.internal
$AKS_IP_WHITELIST = $config.ingress.external_ip_whitelist

# read the vnet and subnet info from kubernetes secret
$AKS_VNET_NAME = $config.networking.vnet
$AKS_SUBNET_NAME = $config.networking.subnet
$AKS_SUBNET_RESOURCE_GROUP = $config.networking.subnet_resource_group

Write-Host "Found vnet info from secret: vnet: $AKS_VNET_NAME, subnet: $AKS_SUBNET_NAME, subnetResourceGroup: $AKS_SUBNET_RESOURCE_GROUP"

if ($ingressExternal -eq "whitelist") {
    Write-Host "Whitelist: $AKS_IP_WHITELIST"

    SaveSecretValue -secretname whitelistip -valueName iprange -value "${AKS_IP_WHITELIST}"
}

Write-Host "Setting up Network Security Group for the subnet"

# setup network security group
$AKS_PERS_NETWORK_SECURITY_GROUP = "$($AKS_PERS_RESOURCE_GROUP.ToLower())-nsg"

if ([string]::IsNullOrWhiteSpace($(az network nsg show -g $AKS_PERS_RESOURCE_GROUP -n $AKS_PERS_NETWORK_SECURITY_GROUP))) {

    Write-Host "Creating the Network Security Group for the subnet"
    az network nsg create -g $AKS_PERS_RESOURCE_GROUP -n $AKS_PERS_NETWORK_SECURITY_GROUP --query "provisioningState"
}
else {
    Write-Host "Network Security Group already exists: $AKS_PERS_NETWORK_SECURITY_GROUP"
}

if ($($config.network_security_group.create_nsg_rules)) {
    Write-Host "Adding or updating rules to Network Security Group for the subnet"
    $sourceTagForAdminAccess = "VirtualNetwork"
    if ($($config.allow_kubectl_from_outside_vnet)) {
        $sourceTagForAdminAccess = "Internet"
        Write-Host "Enabling admin access to cluster from Internet"
    }

    $sourceTagForHttpAccess = "Internet"
    if (![string]::IsNullOrWhiteSpace($AKS_IP_WHITELIST)) {
        $sourceTagForHttpAccess = $AKS_IP_WHITELIST
    }

    DeleteNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP -rulename "HttpPort"
    DeleteNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP -rulename "HttpsPort"

    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_kube_tls" `
        -ruledescription "allow kubectl and HTTPS access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 443 -priority 100 

    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_http" `
        -ruledescription "allow HTTP access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 80 -priority 101
            
    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_ssh" `
        -ruledescription "allow SSH access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 22 -priority 104

    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_mysql" `
        -ruledescription "allow MySQL access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 3306 -priority 205
            
    # if we already have opened the ports for admin access then we're not allowed to add another rule for opening them
    if (($sourceTagForHttpAccess -eq "Internet") -and ($sourceTagForAdminAccess -eq "Internet")) {
        Write-Host "Since we already have rules open port 80 and 443 to the Internet, we do not need to create separate ones for the Internet"
    }
    else {
        if ($($config.ingress.external) -ne "vnetonly") {
            SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
                -rulename "HttpPort" `
                -ruledescription "allow HTTP access from ${sourceTagForHttpAccess}." `
                -sourceTag "${sourceTagForHttpAccess}" -port 80 -priority 500
    
            SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
                -rulename "HttpsPort" `
                -ruledescription "allow HTTPS access from ${sourceTagForHttpAccess}." `
                -sourceTag "${sourceTagForHttpAccess}" -port 443 -priority 501
        }
    }

    $nsgid = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name == '${AKS_PERS_NETWORK_SECURITY_GROUP}'].id" -o tsv
    Write-Host "Found ID for ${AKS_PERS_NETWORK_SECURITY_GROUP}: $nsgid"

    Write-Host "Setting NSG into subnet"
    az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --network-security-group "$nsgid" --query "provisioningState" -o tsv
}

# delete existing containers
kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true


# set Google DNS servers to resolve external  urls
# http://blog.kubernetes.io/2017/04/configuring-private-dns-zones-upstream-nameservers-kubernetes.html
kubectl delete -f "$GITHUB_URL/loadbalancer/dns/upstream.yaml" --ignore-not-found=true
Start-Sleep -Seconds 10
kubectl create -f "$GITHUB_URL/loadbalancer/dns/upstream.yaml"
# to debug dns: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#inheriting-dns-from-the-node

kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

if ($($config.ssl) ) {
    # if the SSL cert is not set in kube secrets then ask for the files
    # ask for tls cert files
    $AKS_SSL_CERT_FOLDER = $($config.ssl_folder)
    if ((!(Test-Path -Path "$AKS_SSL_CERT_FOLDER"))) {
        Write-Error "SSL Folder does not exist: $AKS_SSL_CERT_FOLDER"
    }     

    $AKS_SSL_CERT_FOLDER_UNIX_PATH = (($AKS_SSL_CERT_FOLDER -replace "\\", "/")).ToLower().Trim("/")    

    kubectl delete secret traefik-cert-ahmn -n kube-system --ignore-not-found=true

    Write-Host "Storing TLS certs from $AKS_SSL_CERT_FOLDER_UNIX_PATH as kubernetes secret"
    kubectl create secret generic traefik-cert-ahmn -n kube-system --from-file="$AKS_SSL_CERT_FOLDER_UNIX_PATH/tls.crt" --from-file="$AKS_SSL_CERT_FOLDER_UNIX_PATH/tls.key"
}
else {
    Write-Host "SSL option was not specified in the deployment config: $($config.ssl)"
}

Write-Host "GITHUB_URL: $GITHUB_URL"

if ("$($config.ingress.external)" -ne "vnetonly") {
    Write-Host "Setting up a public load balancer"

    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    if ([string]::IsNullOrWhiteSpace($publicip)) {
        az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
        $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    }  
    Write-Host "Using Public IP: [$publicip]"
}

LoadLoadBalancerStack -baseUrl $GITHUB_URL -ssl $($config.ssl) -ingressInternal "$ingressInternal" -ingressExternal "$ingressExternal" -customerid $customerid -publicIp $publicIp

# setting up traefik
# https://github.com/containous/traefik/blob/master/docs/user-guide/kubernetes.md

$loadBalancerIPResult = GetLoadBalancerIPs
$EXTERNAL_IP = $loadBalancerIPResult.ExternalIP
$INTERNAL_IP = $loadBalancerIPResult.InternalIP

if($($config.ingress.fixloadbalancer)){
    FixLoadBalancers -resourceGroup $AKS_PERS_RESOURCE_GROUP
}

$dnsrecordname = $($config.dns.name)

SaveSecretValue -secretname "dnshostname" -valueName "value" -value $dnsrecordname

if ($($config.dns.create_dns_entries)) {
    SetupDNS -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname -externalIP $EXTERNAL_IP 
}
else {
    Write-Host "To access the urls from your browser, add the following entries in your c:\windows\system32\drivers\etc\hosts file"
    Write-Host "$EXTERNAL_IP $dnsrecordname"
}


