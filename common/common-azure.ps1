# This file contains common functions for Azure
# 
$versionazurecommon = "2018.05.21.02"

Write-Information -MessageData "---- Including common-azure.ps1 version $versionazurecommon -----"
function global:GetCommonAzureVersion() {
    return $versionazurecommon
}

function global:CreateACSCluster([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, [Parameter(Mandatory = $true)][ValidateNotNull()] $config, [ValidateNotNull()][bool] $useAKS) {

    $logfile = "$(get-date -f yyyy-MM-dd-HH-mm)-createacscluster.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    Write-Host "Checking if you're already logged in..."

    Write-Host $config

    DownloadAzCliIfNeeded -version $($config.azcli.version)

    CheckUserIsLoggedIn

    Write-Host "subscription in config: $($config.azure.subscription)"
    SetCurrentAzureSubscription -subscriptionId $($config.azure.subscription)
    
    $subscriptionInfo = $(GetCurrentAzureSubscription)

    $AKS_SUBSCRIPTION_ID = $subscriptionInfo.AKS_SUBSCRIPTION_ID
    $IS_CAFE_ENVIRONMENT = $subscriptionInfo.IS_CAFE_ENVIRONMENT

    $customerid = $($config.customerid)

    Write-Host "Customer ID: $customerid"

    $AKS_PERS_RESOURCE_GROUP = $config.azure.resourceGroup
    $AKS_PERS_LOCATION = $config.azure.location

    CreateResourceGroupIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP -location $AKS_PERS_LOCATION

    # CreateKeyVault -resourceGroup $AKS_PERS_RESOURCE_GROUP -location $AKS_PERS_LOCATION

    $AKS_SUPPORT_WINDOWS_CONTAINERS = $config.azure.create_windows_containers
    $AKS_USE_AZURE_NETWORKING = $config.azure.use_azure_networking

    # if ($AKS_SUPPORT_WINDOWS_CONTAINERS) {
    #     # azure networking is not supported with windows containers
    #     if ($AKS_USE_AZURE_NETWORKING) {
    #         Write-Error "Azure networking is not supported with Windows containers"
    #     }
    # }

    # service account to own the resources
    $AKS_SERVICE_PRINCIPAL_NAME = $config.service_principal.name

    if ([string]::IsNullOrWhiteSpace($AKS_SERVICE_PRINCIPAL_NAME)) {
        $AKS_SERVICE_PRINCIPAL_NAME = "${AKS_PERS_RESOURCE_GROUP}Kubernetes"
    }

    # where to store the SSH keys on local machine
    $AKS_LOCAL_FOLDER = $config.local_folder

    if ([string]::IsNullOrWhiteSpace($AKS_LOCAL_FOLDER)) {$AKS_LOCAL_FOLDER = "C:\kubernetes"}

    if (!(Test-Path -Path "$AKS_LOCAL_FOLDER")) {
        Write-Host "$AKS_LOCAL_FOLDER does not exist.  Creating it..."
        New-Item -ItemType directory -Path $AKS_LOCAL_FOLDER
    }

    AddFolderToPathEnvironmentVariable -folder $AKS_LOCAL_FOLDER

    $SSHKeyInfo = CreateSSHKey -resourceGroup $AKS_PERS_RESOURCE_GROUP -localFolder $AKS_LOCAL_FOLDER
    $AKS_SSH_KEY = $SSHKeyInfo.AKS_SSH_KEY
    $SSH_PRIVATE_KEY_FILE_UNIX_PATH = $SSHKeyInfo.SSH_PRIVATE_KEY_FILE_UNIX_PATH

    # SaveKeyInVault -resourceGroup $AKS_PERS_RESOURCE_GROUP -key "SSH" -value $AKS_SSH_KEY
    # you can retrieve via https://${$AKS_PERS_RESOURCE_GROUP}.vault.azure.net/secrets/SSH
    
    DownloadKubectl -localFolder $AKS_LOCAL_FOLDER -version $($config.kubectl.version)

    # download acs-engine
    # download acs-engine
    $ACS_ENGINE_FILE = "$AKS_LOCAL_FOLDER\acs-engine.exe"
    $SYSTEM_VERSION_ACS_VERSION = [System.Version] "$($config.azure.acs_engine.version)"
    $DESIRED_ACS_ENGINE_VERSION = "v$($config.azure.acs_engine.version)"
    $downloadACSEngine = "n"
    if (!(Test-Path "$ACS_ENGINE_FILE")) {
        $downloadACSEngine = "y"
    }
    else {
        $acsengineversion = acs-engine version
        $acsengineversion = ($acsengineversion -match "^Version: v[0-9.]+")[0]
        $systemAcsVersion = [System.Version] $acsengineversion.Substring($acsengineversion.IndexOf('v') + 1, $acsengineversion.Length - $acsengineversion.IndexOf('v') - 1)
        if ($systemAcsVersion -lt $SYSTEM_VERSION_ACS_VERSION) {
            $downloadACSEngine = "y"
        }
    }
    if ($downloadACSEngine -eq "y") {
        $url = "https://github.com/Azure/acs-engine/releases/download/${DESIRED_ACS_ENGINE_VERSION}/acs-engine-${DESIRED_ACS_ENGINE_VERSION}-windows-amd64.zip"
        Write-Host "Downloading acs-engine.exe from $url to $ACS_ENGINE_FILE"
        if(Test-Path "$ACS_ENGINE_FILE"){
            Remove-Item -Path "$ACS_ENGINE_FILE" -Force
        }

        DownloadFile -url $url -targetFile "$AKS_LOCAL_FOLDER\acs-engine.zip"

        # for some reason the download is not completely done by the time we get here
        Write-Host "Waiting for 10 seconds"
        Start-Sleep -Seconds 10
    
        Expand-Archive -Path "$AKS_LOCAL_FOLDER\acs-engine.zip" -DestinationPath "$AKS_LOCAL_FOLDER" -Force
        Copy-Item -Path "$AKS_LOCAL_FOLDER\acs-engine-${DESIRED_ACS_ENGINE_VERSION}-windows-amd64\acs-engine.exe" -Destination $ACS_ENGINE_FILE
    }
    else {
        Write-Host "acs-engine.exe already exists at $ACS_ENGINE_FILE"    
    }

    Write-Host "ACS Engine version"
    acs-engine version

    $AKS_CLUSTER_NAME = "kubcluster"
    # $AKS_CLUSTER_NAME = Read-Host "Cluster Name: (e.g., fabricnlpcluster)"

    $AKS_PERS_STORAGE_ACCOUNT_NAME = $(CreateStorageIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP -deleteStorageAccountIfExists $config.storage_account.delete_if_exists).AKS_PERS_STORAGE_ACCOUNT_NAME

    $AKS_VNET_NAME = $config.networking.vnet
    $AKS_SUBNET_NAME = $config.networking.subnet
    $AKS_SUBNET_RESOURCE_GROUP = $config.networking.subnet_resource_group

    # see if the user wants to use a specific virtual network
    $VnetInfo = GetVnetInfo -subscriptionId $AKS_SUBSCRIPTION_ID -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP -vnetName $AKS_VNET_NAME -subnetName $AKS_SUBNET_NAME
    $AKS_FIRST_STATIC_IP = $VnetInfo.AKS_FIRST_STATIC_IP
    $AKS_SUBNET_CIDR = $VnetInfo.AKS_SUBNET_CIDR

    # Azure minimum IP: https://github.com/Azure/azure-container-networking/blob/master/docs/acs.md

    CleanResourceGroup -resourceGroup ${AKS_PERS_RESOURCE_GROUP} -location $AKS_PERS_LOCATION -vnet $AKS_VNET_NAME `
        -subnet $AKS_SUBNET_NAME -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP `
        -storageAccount $AKS_PERS_STORAGE_ACCOUNT_NAME

    # Read-Host "continue?"

    Write-Host "checking if Service Principal already exists"
    $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv

    $myscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_PERS_RESOURCE_GROUP}"

    # https://docs.microsoft.com/en-us/azure/active-directory/active-directory-passwords-policy
    if ("$AKS_SERVICE_PRINCIPAL_CLIENTID") {
        Write-Host "Service Principal already exists with name: [$AKS_SERVICE_PRINCIPAL_NAME]"
        if ([string]::IsNullOrWhiteSpace($AKS_SERVICE_PRINCIPAL_CLIENTSECRET)) {
            Write-Host "Could not read client secret from kub secrets so deleting service principal:$AKS_SERVICE_PRINCIPAL_CLIENTID ..."
            az ad sp delete --id "$AKS_SERVICE_PRINCIPAL_CLIENTID" --verbose
            # https://github.com/Azure/azure-cli/issues/1332
            Write-Host "Sleeping to wait for Service Principal to propagate"
            Start-Sleep -Seconds 30;
    
            Write-Host "Creating Service Principal: [$AKS_SERVICE_PRINCIPAL_NAME]"
            $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Owner" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
            # the above command changes the color because it retries role assignment creation
            [Console]::ResetColor()
        }
        else {
            Write-Host "Found past servicePrincipal client secret: $AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
            if ($($config.service_principal.delete_if_exists)) {
                Write-Host "Since delete_if_exists is set in config, deleting service principal:$AKS_SERVICE_PRINCIPAL_CLIENTID ..."
                az ad sp delete --id "$AKS_SERVICE_PRINCIPAL_CLIENTID" --verbose
                # https://github.com/Azure/azure-cli/issues/1332
                Write-Host "Sleeping to wait for Service Principal to propagate"
                Start-Sleep -Seconds 30;
    
                Write-Host "Creating Service Principal: [$AKS_SERVICE_PRINCIPAL_NAME]"
                $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Owner" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
                # the above command changes the color because it retries role assignment creation
                [Console]::ResetColor()
            }
        
        }

        # https://github.com/Azure/azure-cli/issues/1332
        Write-Host "Sleeping to wait for Service Principal to propagate"
        Start-Sleep -Seconds 30;
        $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
        Write-Host "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
    }
    else {
        Write-Host "Creating Service Principal: [$AKS_SERVICE_PRINCIPAL_NAME]"
        $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Contributor" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
        # https://github.com/Azure/azure-cli/issues/1332
        Write-Host "Sleeping to wait for Service Principal to propagate"
        Start-Sleep -Seconds 30;
        [Console]::ResetColor()

        $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
        Write-Host "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
    }

    if ("$AKS_SUBNET_RESOURCE_GROUP") {
        Write-Host "Giving service principal access to vnet resource group: [${AKS_SUBNET_RESOURCE_GROUP}]"
        $subnetscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}"
        az role assignment create --assignee $AKS_SERVICE_PRINCIPAL_CLIENTID --role "contributor" --scope "$subnetscope"
    }

    Write-Host "Create Azure Container Service cluster"

    $mysubnetid = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"

    $dnsNamePrefix = "$AKS_PERS_RESOURCE_GROUP"

    # az acs create --orchestrator-type kubernetes --resource-group $AKS_PERS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_B2ms
    #az acs create --orchestrator-type kubernetes --resource-group fabricnlpcluster --name cluster1 --service-principal="$AKS_SERVICE_PRINCIPAL_CLIENTID" --client-secret="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"  --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_D2 --master-vnet-subnet-id="$mysubnetid" --agent-vnet-subnet-id="$mysubnetid"

    # choose the right template based on user choice
    $templateFile = "acs.template.json"
    if ($useAKS) {
        $templateFile = "aks\kube-deploy.parameters.json"  
    }
    elseif (!"$AKS_VNET_NAME") {
        $templateFile = "acs.template.nosubnet.json"    
    }
    elseif ($AKS_SUPPORT_WINDOWS_CONTAINERS) {
        # https://github.com/Azure/acs-engine/issues/1767
        $templateFile = "acs.template.linuxwindows.json"    
    }
    elseif ($AKS_USE_AZURE_NETWORKING) {
        if ($($config.azure.privatecluster)) {
            $templateFile = "acs.template.azurenetwork.private.json"
        }
        else {
            $templateFile = "acs.template.azurenetwork.json"                         
        }
    }

    Write-Host "Using template: $baseUrl/azure/$templateFile"

    $AKS_LOCAL_TEMP_FOLDER = "$AKS_LOCAL_FOLDER\$AKS_PERS_RESOURCE_GROUP\temp"
    if (!(Test-Path -Path "$AKS_LOCAL_TEMP_FOLDER")) {
        New-Item -ItemType directory -Path "$AKS_LOCAL_TEMP_FOLDER"
    }

    # sometimes powershell starts in a strange folder where the current user doesn't have permissions
    # so CD into the temp folder to avoid errors
    Set-Location -Path $AKS_LOCAL_TEMP_FOLDER

    $output = "$AKS_LOCAL_TEMP_FOLDER\acs.json"
    Write-Host "Downloading parameters file from github to $output"
    if (Test-Path $output) {
        Remove-Item $output
    }

    # download the template file from github
    if ($baseUrl.StartsWith("http")) { 
        Write-Host "Downloading file: $baseUrl/azure/$templateFile"
        Invoke-WebRequest -Uri "$baseUrl/azure/$templateFile" -OutFile $output -ContentType "text/plain; charset=utf-8"
    }
    else {
        Copy-Item -Path "$baseUrl/azure/$templateFile" -Destination "$output"
    }

    # subnet CIDR to mask
    # https://doc.m0n0.ch/quickstartpc/intro-CIDR.html
    $kubernetesVersion = $(Coalesce $($config.kubernetes.version) "1.9")
    $masterVMSize = $(Coalesce $($config.azure.masterVMSize) "Standard_DS2_v2")
    $workerVMSize = $(Coalesce $($config.azure.workerVMSize) "Standard_DS2_v2")

    $WINDOWS_PASSWORD = "replacepassword1234$"
    Write-Host "replacing values in the acs.json file"
    Write-Host "KUBERNETES-VERSION: $kubernetesVersion"
    Write-Host "MASTER_VMSIZE: $masterVMSize"
    Write-Host "WORKER-VMSIZE: $workerVMSize"
    Write-Host "AKS_SSH_KEY: $AKS_SSH_KEY"
    Write-Host "AKS_SERVICE_PRINCIPAL_CLIENTID: $AKS_SERVICE_PRINCIPAL_CLIENTID"
    Write-Host "AKS_SERVICE_PRINCIPAL_CLIENTSECRET: $AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
    Write-Host "SUBNET: ${mysubnetid}"
    Write-Host "DNS NAME: ${dnsNamePrefix}"
    Write-Host "FIRST STATIC IP: $AKS_FIRST_STATIC_IP"
    Write-Host "WINDOWS PASSWORD: $WINDOWS_PASSWORD"
    Write-Host "AKS_SUBNET_CIDR: $AKS_SUBNET_CIDR"
    $MyFile = (Get-Content $output) | 
        Foreach-Object {$_ -replace 'REPLACE-KUBERNETES-VERSION', "${kubernetesVersion}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-MASTER_VMSIZE', "${masterVMSize}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-WORKER-VMSIZE', "${workerVMSize}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-SSH-KEY', "${AKS_SSH_KEY}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-CLIENTID', "${AKS_SERVICE_PRINCIPAL_CLIENTID}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-CLIENTSECRET', "${AKS_SERVICE_PRINCIPAL_CLIENTSECRET}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-SUBNET', "${mysubnetid}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-DNS-NAME-PREFIX', "${dnsNamePrefix}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-FIRST-STATIC-IP', "${AKS_FIRST_STATIC_IP}"}  | 
        Foreach-Object {$_ -replace 'REPLACE-WINDOWS-PASSWORD', "${WINDOWS_PASSWORD}"}  | 
        Foreach-Object {$_ -replace 'REPLACE_VNET_CIDR', "${AKS_SUBNET_CIDR}"}  

    

    # have to do it this way instead of Outfile so we can get a UTF-8 file without BOM
    # from https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($output, $MyFile, $Utf8NoBomEncoding)

    $acsoutputfolder = "$AKS_LOCAL_TEMP_FOLDER\_output\$dnsNamePrefix"
    if (!(Test-Path -Path "$acsoutputfolder")) {
        New-Item -ItemType directory -Path "$acsoutputfolder"
    }

    Write-Host "Deleting everything in the output folder"
    Remove-Item -Path $acsoutputfolder -Recurse -Force

    # to get valid kubernetes versions: acs-engine orchestrators --orchestrator kubernetes

    if ($useAKS) {

    }
    else {
        Write-Host "Checking if acs-engine supports kubernetes version= $kubernetesVersion"
        acs-engine orchestrators --orchestrator kubernetes --version "$kubernetesVersion"    
    }

    if (!$useAKS) {

        Write-Host "Generating ACS engine template"

        # acs-engine deploy --subscription-id "$AKS_SUBSCRIPTION_ID" `
        #                     --dns-prefix $dnsNamePrefix --location $AKS_PERS_LOCATION `
        #                     --resource-group $AKS_PERS_RESOURCE_GROUP `
        #                     --api-model "$output" `
        #                     --output-directory "$acsoutputfolder"

        acs-engine generate $output --output-directory $acsoutputfolder

        if ($?) {            
            Write-Host "ACS Engine generated the template successfully"            
        }
        else {            
            exit 1          
        } 
    }

    if ($AKS_SUPPORT_WINDOWS_CONTAINERS) {
        Write-Host "Adding subnet to azuredeploy.json to work around acs-engine bug"
        $outputdeployfile = "$acsoutputfolder\azuredeploy.json"
        # https://github.com/Azure/acs-engine/issues/1767
        # "subnet": "${mysubnetid}"
        # replace     "vnetSubnetID": "[parameters('masterVnetSubnetID')]"
        # "subnet": "[parameters('masterVnetSubnetID')]"

        #there is a bug in acs-engine: https://github.com/Azure/acs-engine/issues/1767
        $mydeployjson = Get-Content -Raw -Path $outputdeployfile | ConvertFrom-Json
        $mydeployjson.variables | Add-Member -Type NoteProperty -Name 'subnet' -Value "[parameters('masterVnetSubnetID')]"
        $outjson = ConvertTo-Json -InputObject $mydeployjson -Depth 10
        Set-Content -Path $outputdeployfile -Value $outjson  
    }

    # --orchestrator-version 1.8 `
    # --ssh-key-value 

    # az acs create `
    #     --orchestrator-type kubernetes `
    #     --dns-prefix ${dnsNamePrefix} `
    #     --resource-group $AKS_PERS_RESOURCE_GROUP `
    #     --name $AKS_CLUSTER_NAME `
    #     --location $AKS_PERS_LOCATION `
    #     --service-principal="$AKS_SERVICE_PRINCIPAL_CLIENTID" `
    #     --client-secret="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"  `
    #     --agent-count=3 --agent-vm-size Standard_D2 `
    #     --master-vnet-subnet-id="$mysubnetid" `
    #     --agent-vnet-subnet-id="$mysubnetid"

    $deploymentfile="$acsoutputfolder\azuredeploy.json"
    if($useAKS){
        $deploymentfile="aks\kube-managed.json"
    }
    
    Write-Host "Validating deployment"
    az group deployment validate `
        --template-file "$deploymentfile" `
        --resource-group $AKS_PERS_RESOURCE_GROUP `
        --parameters "$acsoutputfolder\azuredeploy.parameters.json"

    Write-Host "Starting deployment..."

    az group deployment create `
        --template-file "$deploymentfile" `
        --resource-group $AKS_PERS_RESOURCE_GROUP -n $AKS_CLUSTER_NAME `
        --parameters "$acsoutputfolder\azuredeploy.parameters.json" `
        --verbose	

    # Write-Host "Saved to $acsoutputfolder\azuredeploy.json"

    # if joining a vnet, and not using azure networking then we have to manually set the route-table
    if ("$AKS_VNET_NAME") {
        if (!$AKS_USE_AZURE_NETWORKING) {
            Write-Host "Attaching route table"
            # https://github.com/Azure/acs-engine/blob/master/examples/vnet/k8s-vnet-postdeploy.sh
            $rt = az network route-table list -g "${AKS_PERS_RESOURCE_GROUP}" --query "[?name != 'temproutetable'].id" -o tsv
            $nsg = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name != 'tempnsg'].id" -o tsv

            Write-Host "new route: $rt"
            Write-Host "new nsg: $nsg"

            az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --route-table "$rt" --network-security-group "$nsg"
        
            Write-Host "Sleeping to let subnet be updated"
            Start-Sleep -Seconds 30

            az network route-table delete --name temproutetable --resource-group $AKS_PERS_RESOURCE_GROUP
            az network nsg delete --name tempnsg --resource-group $AKS_PERS_RESOURCE_GROUP
        }
    }

    # az.cmd acs kubernetes get-credentials `
    #     --resource-group=$AKS_PERS_RESOURCE_GROUP `
    #     --name=$AKS_CLUSTER_NAME

    # Write-Host "Getting kube config by ssh to the master VM"
    # $MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
    # $SSH_PRIVATE_KEY_FILE = "$env:userprofile\.ssh\id_rsa"

    # if (Get-Module -ListAvailable -Name Posh-SSH) {
    # }
    # else {
    #     Install-Module Posh-SSH -Scope CurrentUser -Force
    # }

    # # from http://www.powershellmagazine.com/2014/07/03/posh-ssh-open-source-ssh-powershell-module/
    # $User = "azureuser"
    # $Credential = New-Object System.Management.Automation.PSCredential($User, (new-object System.Security.SecureString))
    # # New-SSHSession -ComputerName ${MASTER_VM_NAME} -KeyFile "${SSH_PRIVATE_KEY_FILE}" -Credential $Credential -AcceptKey -Verbose -Force
    # # Invoke-SSHCommand -Command "cat ./.kube/config" -SessionId 0 
    # Get-SCPFile -LocalFile "$env:userprofile\.kube\config" -RemoteFile "./.kube/config" -ComputerName ${MASTER_VM_NAME} -KeyFile "${SSH_PRIVATE_KEY_FILE}" -Credential $Credential -AcceptKey -Verbose -Force
    # Remove-SSHSession -SessionId 0

    # store kube config in local folder
    if (!(Test-Path -Path "$env:userprofile\.kube")) {
        Write-Host "$env:userprofile\.kube does not exist.  Creating it..."
        New-Item -ItemType directory -Path "$env:userprofile\.kube"
    }
    if (!(Test-Path -Path "$AKS_LOCAL_TEMP_FOLDER\.kube")) {
        New-Item -ItemType directory -Path "$AKS_LOCAL_TEMP_FOLDER\.kube"
    }

    $privateIpOfMasterVM = $(GetPrivateIPofMasterVM -resourceGroup $AKS_PERS_RESOURCE_GROUP).PrivateIP
    $publicNameOfMasterVM = $(GetPublicNameofMasterVM -resourceGroup $AKS_PERS_RESOURCE_GROUP).Name
    $kubeconfigjsonfile = "$acsoutputfolder\kubeconfig\kubeconfig.$AKS_PERS_LOCATION.json"

    if ($IS_CAFE_ENVIRONMENT) {
        Write-Host "Replacing master vm name, [$publicNameOfMasterVM], with private ip, [$privateIpOfMasterVM], in kube config file"
        (Get-Content "$kubeconfigjsonfile").replace("$publicNameOfMasterVM", "$privateIpOfMasterVM") | Set-Content "$kubeconfigjsonfile"    
    }

    Copy-Item -Path "$kubeconfigjsonfile" -Destination "$env:userprofile\.kube\config"

    Copy-Item -Path "$kubeconfigjsonfile" -Destination "$AKS_LOCAL_TEMP_FOLDER\.kube\config"

    # If ((Get-Content "$($env:windir)\system32\Drivers\etc\hosts" ) -notcontains "127.0.0.1 hostname1")  
    #  {ac -Encoding UTF8  "$($env:windir)\system32\Drivers\etc\hosts" "127.0.0.1 hostname1" }

    $MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
    Write-Host "You can connect to master VM in Git Bash for debugging using:"
    Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${MASTER_VM_NAME}"

    Stop-Transcript
}

function global:ConfigureKubernetes([Parameter(Mandatory = $true)][ValidateNotNull()] $config){
    # $WINDOWS_PASSWORD

    $logfile = "$(get-date -f yyyy-MM-dd-HH-mm)-configurekubernetes.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    $resourceGroup = $($config.azure.resourceGroup)
    Write-Host "Resource Group: $resourceGroup"
    $customerid = $($config.customerid)
    Write-Host "CustomerID: $customerid"

    $storageAccountName="${resourceGroup}storage"

    Write-Host "Check nodes via kubectl"
    # set the environment variable so kubectl gets the new config
    $env:KUBECONFIG = "${HOME}\.kube\config"
    kubectl get nodes -o=name

    # wait until the nodes are up
    $nodeCount = 0

    while ($nodeCount -lt 3) {
        $lines = kubectl get nodes -o=name | Measure-Object -Line
        $nodeCount = $lines.Lines
        Start-Sleep -s 10
    }

    # create storage account

    Write-Host "Get storage account key"
    $storageKey = az storage account keys list --resource-group $resourceGroup --account-name $storageAccountName --query "[0].value" --output tsv

    # Write-Host "Storagekey: [$STORAGE_KEY]"

    Write-Host "Creating kubernetes secret for Azure Storage Account: azure-secret"
    kubectl create secret generic azure-secret --from-literal=resourcegroup="${resourceGroup}" --from-literal=azurestorageaccountname="${storageAccountName}" --from-literal=azurestorageaccountkey="${storageKey}"
    Write-Host "Creating kubernetes secret for customerid: customerid"
    kubectl create secret generic customerid --from-literal=value=$customerid
    if (![string]::IsNullOrEmpty($WINDOWS_PASSWORD)) {
        Write-Host "Creating kubernetes secret for windows VM"
        kubectl create secret generic windowspassword --from-literal=password="$WINDOWS_PASSWORD"
    }

    kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide

    # kubectl patch deployment kube-dns-v20 -n kube-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","image":"172.20.34.206:5000/myapp:img:3.0"}]}}}}'
    # kubectl patch deployment kube-dns-v20 -n kube-system -p '{"spec":{"template":{"spec":{"restartPolicy":"Never"}}}}'

    # Write-Host "Restarting DNS Pods (sometimes they get in a CrashLoopBackoff loop)"
    # $failedItems = kubectl get pods -l k8s-app=kube-dns -n kube-system -o jsonpath='{range.items[*]}{.metadata.name}{\"\n\"}{end}'
    # ForEach ($line in $failedItems) {
    #     Write-Host "Deleting pod $line"
    #     kubectl delete pod $line -n kube-system
    # } 

    if ($($config.azure.sethostfile)) {
        SetHostFileInVms -resourceGroup $resourceGroup
        SetupCronTab -resourceGroup $resourceGroup
    }

    Write-Host "Removing extra stuff that acs-engine creates"
    # k8s-master-lb-24203516
    # k8s-master-ip-prod-kub-sjtn-rg-24203516

    # /subscriptions/f8a42a3a-8b22-4be4-8413-0b6911c77242/resourceGroups/Prod-Kub-AHMN-RG/providers/Microsoft.Network/networkInterfaces/k8s-master-37819884-nic-0

    # command to update hosts
    # grep -v " k8s-master-37819884-0" /etc/hosts | grep -v "k8s-linuxagent-37819884-0" - | grep -v "k8s-linuxagent-37819884-1" - | grep -v "prod-kub-ahmn-rg.westus.cloudapp.azure.com" - | tee /etc/hosts
    # | ( cat - && echo "foo" && echo "bar")
    # | tee /etc/hosts

    # copy the file into /etc/cron.hourly/
    # chmod +x ./restartkubedns.sh
    # sudo mv ./restartkubedns.sh /etc/cron.hourly/
    # grep CRON /var/log/syslog
    # * * * * * /etc/cron.hourly/restartkubedns.sh >>/tmp/restartkubedns.log
    # https://stackoverflow.com/questions/878600/how-to-create-a-cron-job-using-bash-automatically-without-the-interactive-editor
    # crontab -l | { cat; echo "*/10 * * * * /etc/cron.hourly/restartkubedns.sh >>/tmp/restartkubedns.log"; } | crontab -
    # az vm extension set --resource-group Prod-Kub-AHMN-RG --vm-name k8s-master-37819884-0 --name customScript --publisher Microsoft.Azure.Extensions --protected-settings "{'commandToExecute': 'whoami;touch /tmp/me.txt'}"
    # az vm run-command invoke -g Prod-Kub-AHMN-RG -n k8s-master-37819884-0 --command-id RunShellScript --scripts "whomai"
    # az vm run-command invoke -g Prod-Kub-AHMN-RG -n k8s-master-37819884-0 --command-id RunShellScript --scripts "crontab -l | { cat; echo '*/10 * * * * /etc/cron.hourly/restartkubedns.sh >>/tmp/restartkubedns.log 2>&1'; } | crontab -"

    Write-Host "Add label to master node"
    FixLabelOnMaster

    Write-Host "Run the following to see status of the cluster"
    Write-Host "kubectl get deployments,pods,services,ingress,secrets --namespace=kube-system -o wide"

    Stop-Transcript
}

function global:SetupAzureLoadBalancer([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, [Parameter(Mandatory = $true)][ValidateNotNull()] $config) {
   
    $logfile = "$(get-date -f yyyy-MM-dd-HH-mm)-SetupAzureLoadBalancer.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    $AKS_IP_WHITELIST = ""
    
    CheckUserIsLoggedIn

    SetCurrentAzureSubscription -subscriptionId $($config.azure.subscription)
    
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
    
    $ingressExternalType = $config.ingress.external.type
    $ingressInternalType = $config.ingress.internal.type
    $AKS_IP_WHITELIST = $config.ingress.external.whitelist
    
    # read the vnet and subnet info from kubernetes secret
    $AKS_VNET_NAME = $config.networking.vnet
    $AKS_SUBNET_NAME = $config.networking.subnet
    $AKS_SUBNET_RESOURCE_GROUP = $config.networking.subnet_resource_group
    
    Write-Host "Found vnet info from secret: vnet: $AKS_VNET_NAME, subnet: $AKS_SUBNET_NAME, subnetResourceGroup: $AKS_SUBNET_RESOURCE_GROUP"
    
    if ($ingressExternalType -eq "whitelist") {
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
    kubectl delete -f "$baseUrl/loadbalancer/dns/upstream.yaml" --ignore-not-found=true
    Start-Sleep -Seconds 10
    kubectl create -f "$baseUrl/loadbalancer/dns/upstream.yaml"
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
    
    Write-Host "baseUrl: $baseUrl"

    $externalSubnetName=""
    if($($config.ingress.external.subnet)){
        $externalSubnetName=$($config.ingress.external.subnet);
    }

    $externalIp=""
    if($($config.ingress.external.ipAddress)){
        $externalIp = $($config.ingress.external.ipAddress);
    }
    elseif ("$($config.ingress.external.type)" -ne "vnetonly") {
        Write-Host "Setting up a public load balancer"
    
        $externalip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
        if ([string]::IsNullOrWhiteSpace($externalip)) {
            az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
            $externalip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
        }  
        Write-Host "Using Public IP: [$externalip]"
    }

    $internalSubnetName=""
    if($($config.ingress.internal.subnet)){
        $internalSubnetName=$($config.ingress.internal.subnet);
    }

    $internalIp=""
    if($($config.ingress.internal.ipAddress)){
        $internalIp = $($config.ingress.internal.ipAddress);
    }
    
    LoadLoadBalancerStack -baseUrl $baseUrl -ssl $($config.ssl) `
                            -ingressInternalType "$ingressInternalType" -ingressExternalType "$ingressExternalType" `
                            -customerid $customerid -isOnPrem $false `
                            -externalSubnetName "$externalSubnetName" -externalIp "$externalip" `
                            -internalSubnetName "$internalSubnetName" -internalIp "$internalIp"
    
    # setting up traefik
    # https://github.com/containous/traefik/blob/master/docs/user-guide/kubernetes.md
    
    $loadBalancerIPResult = GetLoadBalancerIPs
    $EXTERNAL_IP = $loadBalancerIPResult.ExternalIP
    $INTERNAL_IP = $loadBalancerIPResult.InternalIP
    
    if ($($config.ingress.fixloadbalancer)) {
        FixLoadBalancers -resourceGroup $AKS_PERS_RESOURCE_GROUP
    }
    
    # if($($config.ingress.loadbalancerconfig)){
    #     MoveInternalLoadBalancerToIP -subscriptionId $($(GetCurrentAzureSubscription).AKS_SUBSCRIPTION_ID) -resourceGroup $AKS_PERS_RESOURCE_GROUP `
    #                                 -subnetResourceGroup $config.ingress.loadbalancerconfig.subnet_resource_group -vnetName $config.ingress.loadbalancerconfig.vnet `
    #                                 -subnetName $config.ingress.loadbalancerconfig.subnet -newIpAddress $config.ingress.loadbalancerconfig.privateIpAddress
    # }

    $dnsrecordname = $($config.dns.name)
    
    SaveSecretValue -secretname "dnshostname" -valueName "value" -value $dnsrecordname
    
    if ($($config.dns.create_dns_entries)) {
        SetupDNS -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname -externalIP $EXTERNAL_IP 
    }
    else {
        Write-Host "To access the urls from your browser, add the following entries in your c:\windows\system32\drivers\etc\hosts file"
        Write-Host "$EXTERNAL_IP $dnsrecordname"
    }        

    Stop-Transcript

}

function global:CreateBareMetalCluster([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, [Parameter(Mandatory = $true)][ValidateNotNull()] $config) {   
    DownloadAzCliIfNeeded -version $($config.azcli.version)
    
    CheckUserIsLoggedIn
    
    SetCurrentAzureSubscription -subscriptionId $($config.azure.subscription)
    
    $subscriptionInfo = $(GetCurrentAzureSubscription)
    
    $AKS_SUBSCRIPTION_ID = $subscriptionInfo.AKS_SUBSCRIPTION_ID
    
    $customerid = $($config.customerid)
    
    Write-Host "Customer ID: $customerid"
    
    $AKS_PERS_RESOURCE_GROUP = $config.azure.resourceGroup
    $AKS_PERS_LOCATION = $config.azure.location
    
    CreateResourceGroupIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP -location $AKS_PERS_LOCATION
    
    $AKS_SUPPORT_WINDOWS_CONTAINERS = $config.azure.create_windows_containers
    
    # service account to own the resources
    $AKS_SERVICE_PRINCIPAL_NAME = $config.service_principal.name
    
    if ([string]::IsNullOrWhiteSpace($AKS_SERVICE_PRINCIPAL_NAME)) {
        $AKS_SERVICE_PRINCIPAL_NAME = "${AKS_PERS_RESOURCE_GROUP}Kubernetes"
    }
    
    $AKS_LOCAL_FOLDER = $config.local_folder
    
    if ([string]::IsNullOrWhiteSpace($AKS_LOCAL_FOLDER)) {$AKS_LOCAL_FOLDER = "C:\kubernetes"}
    
    if (!(Test-Path -Path "$AKS_LOCAL_FOLDER")) {
        Write-Host "$AKS_LOCAL_FOLDER does not exist.  Creating it..."
        New-Item -ItemType directory -Path $AKS_LOCAL_FOLDER
    }
    
    AddFolderToPathEnvironmentVariable -folder $AKS_LOCAL_FOLDER
    
    $SSHKeyInfo = CreateSSHKey -resourceGroup $AKS_PERS_RESOURCE_GROUP -localFolder $AKS_LOCAL_FOLDER
    $SSH_PUBLIC_KEY_FILE = $SSHKeyInfo.SSH_PUBLIC_KEY_FILE
    $SSH_PRIVATE_KEY_FILE_UNIX_PATH = $SSHKeyInfo.SSH_PRIVATE_KEY_FILE_UNIX_PATH
    
    DownloadKubectl -localFolder $AKS_LOCAL_FOLDER -version $($config.kubectl.version)
    
    if ([string]::IsNullOrEmpty($(kubectl config current-context 2> $null))) {
        Write-Host "kube config is not set"
    }
    else {
        if (${AKS_PERS_RESOURCE_GROUP} -ieq $(kubectl config current-context 2> $null) ) {
            Write-Host "Current kub config points to this cluster"
        }
        else {
            $clustername = "${AKS_PERS_RESOURCE_GROUP}"
            $fileToUse = "$AKS_LOCAL_FOLDER\$clustername\temp\.kube\config"
            if (Test-Path $fileToUse) {
                SwitchToKubCluster -folderToUse "${AKS_LOCAL_FOLDER}\${clustername}" 
            }
            else {
                CleanKubConfig
            }        
        }        
    }
    
    $storageInfo = $(CreateStorageIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP -deleteStorageAccountIfExists $config.storage_account.delete_if_exists)
    $AKS_PERS_STORAGE_ACCOUNT_NAME = $storageInfo.AKS_PERS_STORAGE_ACCOUNT_NAME
    $STORAGE_KEY = $storageInfo.STORAGE_KEY
    
    $AKS_VNET_NAME = $config.networking.vnet
    $AKS_SUBNET_NAME = $config.networking.subnet
    $AKS_SUBNET_RESOURCE_GROUP = $config.networking.subnet_resource_group
    
    # see if the user wants to use a specific virtual network
    $VnetInfo = GetVnetInfo -subscriptionId $AKS_SUBSCRIPTION_ID -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP -vnetName $AKS_VNET_NAME -subnetName $AKS_SUBNET_NAME
    $AKS_SUBNET_ID = $VnetInfo.AKS_SUBNET_ID
    
    CleanResourceGroup -resourceGroup ${AKS_PERS_RESOURCE_GROUP} -location $AKS_PERS_LOCATION -vnet $AKS_VNET_NAME `
        -subnet $AKS_SUBNET_NAME -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP `
        -storageAccount $AKS_PERS_STORAGE_ACCOUNT_NAME
    
    Write-Host "Using Storage Account: $AKS_PERS_STORAGE_ACCOUNT_NAME"
    
    $SHARE_NAME = "data"
    CreateShareInStorageAccount -storageAccountName $AKS_PERS_STORAGE_ACCOUNT_NAME -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename "$SHARE_NAME"
    
    $NETWORK_SECURITY_GROUP = "cluster-nsg"
    Write-Host "Creating network security group: $NETWORK_SECURITY_GROUP"
    $nsg = az network nsg create --name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP --query "id" -o tsv 
    
    if ($($config.network_security_group.create_nsg_rules)) {
        Write-Host "Creating rule: allow_ssh"
        az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n allow_ssh --priority 100 `
            --source-address-prefixes "*" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow `
            --protocol Tcp --description "allow ssh access." `
            --query "provisioningState" -o tsv
    
        Write-Host "Creating rule: allow_rdp"
        az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n allow_rdp `
            --priority 101 `
            --source-address-prefixes "*" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges 3389 --access Allow `
            --protocol Tcp --description "allow RDP access." `
            --query "provisioningState" -o tsv
    
        $sourceTagForHttpAccess = "Internet"
        if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpPort" --nsg-name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
            Write-Host "Creating rule: HttpPort"
            az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
                --source-address-prefixes $sourceTagForHttpAccess --source-port-ranges '*' `
                --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
                --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
                --query "provisioningState" -o tsv
        }
        else {
            Write-Host "Updating rule: HttpPort"
            az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
                --source-address-prefixes $sourceTagForHttpAccess --source-port-ranges '*' `
                --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
                --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
                --query "provisioningState" -o tsv
        }
    
        if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpsPort" --nsg-name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
            Write-Host "Creating rule: HttpsPort"
            az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
                --source-address-prefixes $sourceTagForHttpAccess --source-port-ranges '*' `
                --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
                --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
                --query "provisioningState" -o tsv
        }
        else {
            Write-Host "Updating rule: HttpsPort"
            az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
                --source-address-prefixes $sourceTagForHttpAccess --source-port-ranges '*' `
                --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
                --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
                --query "provisioningState" -o tsv
        }    
    }
    
    $nsgid = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name == '${NETWORK_SECURITY_GROUP}'].id" -o tsv
    Write-Host "Found ID for ${AKS_PERS_NETWORK_SECURITY_GROUP}: $nsgid"
    
    Write-Host "Setting NSG into subnet"
    az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --network-security-group "$nsgid" --query "provisioningState" -o tsv
    
    # to list available images: az vm image list --output table
    # to list CentOS images: az vm image list --offer CentOS --publisher OpenLogic --all --output table
    $urn = "OpenLogic:CentOS:7.4:latest"
    
    Write-Host "Creating master"
    $VMInfo = CreateVM -vm "k8s-master" -resourceGroup $AKS_PERS_RESOURCE_GROUP `
        -subnetId $AKS_SUBNET_ID `
        -networkSecurityGroup $NETWORK_SECURITY_GROUP `
        -publicKeyFile $SSH_PUBLIC_KEY_FILE `
        -image $urn
    
    Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@$($VMInfo.IP)"
    Write-Host "Run: curl -sSL ${$baseUrl}/onprem/main.sh | bash"
    
    Write-Host "Creating linux vm 1"
    $VMInfo = CreateVM -vm "k8s-linux-agent-1" -resourceGroup $AKS_PERS_RESOURCE_GROUP `
        -subnetId $AKS_SUBNET_ID `
        -networkSecurityGroup $NETWORK_SECURITY_GROUP `
        -publicKeyFile $SSH_PUBLIC_KEY_FILE `
        -image $urn
    
    Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@$($VMInfo.IP)"
    
    Write-Host "Creating linux vm 2"
    $VMInfo = CreateVM -vm "k8s-linux-agent-2" -resourceGroup $AKS_PERS_RESOURCE_GROUP `
        -subnetId $AKS_SUBNET_ID `
        -networkSecurityGroup $NETWORK_SECURITY_GROUP `
        -publicKeyFile $SSH_PUBLIC_KEY_FILE `
        -image $urn
    
    Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@$($VMInfo.IP)"
    
    if ($AKS_SUPPORT_WINDOWS_CONTAINERS -eq "y") {
        Write-Host "Creating windows vm 1"
        $vm = "k8swindows1"
        $PUBLIC_IP_NAME = "${vm}PublicIP"
        $ip = az network public-ip create --name $PUBLIC_IP_NAME `
            --resource-group $AKS_PERS_RESOURCE_GROUP `
            --allocation-method Static --query "publicIp.ipAddress" -o tsv
    
        az network nic create `
            --resource-group $AKS_PERS_RESOURCE_GROUP `
            --name "${vm}-nic" `
            --subnet $AKS_SUBNET_ID `
            --network-security-group $NETWORK_SECURITY_GROUP `
            --public-ip-address $PUBLIC_IP_NAME
    
        # Update for your admin password
        $AdminPassword = "ChangeYourAdminPassword1"
    
        # to list Windows images: az vm image list --offer WindowsServer --all --output table
        $urn = "MicrosoftWindowsServer:WindowsServerSemiAnnual:Datacenter-Core-1709-with-Containers-smalldisk:1709.0.20171012"
        $urn = "Win2016Datacenter"
        az vm create --resource-group $AKS_PERS_RESOURCE_GROUP --name $vm `
            --image "$urn" `
            --size Standard_DS2_v2 `
            --admin-username azureuser --admin-password $AdminPassword `
            --nics "${vm}-nic" `
            --query "provisioningState" -o tsv
    
        # https://stackoverflow.com/questions/43914269/how-to-run-simple-custom-commands-on-a-azure-vm-win-7-8-10-server-post-deploy
        # az vm extension set -n CustomScriptExtension --publisher Microsoft.Compute --version 1.8 --vm-name DVWinServerVMB --resource-group DVResourceGroup --settings "{'commandToExecute': 'powershell.exe md c:\\test'}"
    
    }
    
    Write-Host "For mounting azure storage as a shared drive"
    Write-Host "Storage Account Name: $AKS_PERS_STORAGE_ACCOUNT_NAME"
    Write-Host "Share Name: $SHARE_NAME"
    Write-Host "Storage key: $STORAGE_KEY"        
}

function global:StartVMsInResourceGroup([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $resourceGroup) {
    az vm start --ids $(az vm list -g $resourceGroup --query "[].id" -o tsv) 
}
function global:StopVMsInResourceGroup([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $resourceGroup) {
    az vm stop --ids $(az vm list -g $resourceGroup --query "[].id" -o tsv) 
}
function global:RenewAzureToken() {
    az account clear
    az login
}
function global:LaunchAzureKubernetesDashboard() {
    # launch Kubernetes dashboard
    $launchJob = $true
    $myPortArray = 8001, 8002, 8003, 8004, 8005, 8006, 8007, 8008, 8009, 8010, 8011, 8012, 8013, 8014, 8015, 8016, 8017, 8018, 8019, 8020, 8021, 8022, 8023, 8024, 8025, 8026, 8027, 8028, 8029, 8030, 8031, 8032, 8033, 8034, 8035, 8036, 8037, 8038, 8039
    $port = $(FindOpenPort -portArray $myPortArray).Port
    Write-Host "Starting Kub Dashboard on port $port"
    # $existingProcess = Get-ProcessByPort 8001
    # if (!([string]::IsNullOrWhiteSpace($existingProcess))) {
    #     Do { $confirmation = Read-Host "Another process is listening on 8001.  Do you want to kill that process? (y/n)"}
    #     while ([string]::IsNullOrWhiteSpace($confirmation))
                
    #     if ($confirmation -eq "y") {
    #         Stop-ProcessByPort 8001
    #     }
    #     else {
    #         $launchJob = $false
    #     }
    # }
    
    if ($launchJob) {
        # https://stackoverflow.com/questions/19834643/powershell-how-to-pre-evaluate-variables-in-a-scriptblock-for-start-job
        $sb = [scriptblock]::Create("kubectl proxy -p $port")
        $job = Start-Job -Name "KubDashboard" -ScriptBlock $sb -ErrorAction Stop
        Wait-Job $job -Timeout 5;
        Write-Host "job state: $($job.state)"  
        Receive-Job -Job $job 6>&1  
    }
    
    # if ($job.state -eq 'Failed') {
    #     Receive-Job -Job $job
    #     Stop-ProcessByPort 8001
    # }
                
    # Write-Host "Your kubeconfig file is here: $env:KUBECONFIG"
    $kubectlversion = $(kubectl version --short=true)[1]
    if ($kubectlversion -match "v1.8") {
        Write-Host "Launching http://localhost:$port/api/v1/namespaces/kube-system/services/kubernetes-dashboard/proxy in the web browser"
        Start-Process -FilePath "http://localhost:$port/api/v1/namespaces/kube-system/services/kubernetes-dashboard/proxy";
    }
    else {
        Write-Host "Launching http://localhost:$port/api/v1/namespaces/kube-system/services/http:kubernetes-dashboard:/proxy/ in the web browser"
        Write-Host "Click Skip on login screen";
        Start-Process -FilePath "http://localhost:$port/api/v1/namespaces/kube-system/services/http:kubernetes-dashboard:/proxy/";
    }            
    
}

function global:ShowSSHCommandsToVMs() {
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

    $AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv

    $AKS_LOCAL_FOLDER = Read-Host "Folder to store SSH keys (default: c:\kubernetes)"
    if ([string]::IsNullOrWhiteSpace($AKS_LOCAL_FOLDER)) {$AKS_LOCAL_FOLDER = "C:\kubernetes"}

    $AKS_FOLDER_FOR_SSH_KEY = "$AKS_LOCAL_FOLDER\ssh\$AKS_PERS_RESOURCE_GROUP"
    $SSH_PRIVATE_KEY_FILE = "$AKS_FOLDER_FOR_SSH_KEY\id_rsa"
    $SSH_PRIVATE_KEY_FILE_UNIX_PATH = "/" + (($SSH_PRIVATE_KEY_FILE -replace "\\", "/") -replace ":", "").ToLower().Trim("/")                                       
    # $MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
    # Write-Host "You can connect to master VM in Git Bash for debugging using:"
    # Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${MASTER_VM_NAME}"            

    $virtualmachines = az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        $firstpublicip = az vm list-ip-addresses -g $AKS_PERS_RESOURCE_GROUP -n $vm --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv
        if ([string]::IsNullOrEmpty($firstpublicip)) {
            $firstpublicip = az vm show -g $AKS_PERS_RESOURCE_GROUP -n $vm -d --query privateIps -otsv
            $firstpublicip = $firstpublicip.Split(",")[0]
        }
        Write-Host "Connect to ${vm}:"
        Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${firstpublicip}"            
    }

    Write-Host "Command to show errors: sudo journalctl -xef --priority 0..3"
    Write-Host "Command to see apiserver logs: sudo journalctl -fu kube-apiserver"
    Write-Host "Command to see kubelet status: sudo systemctl status kubelet"
    # sudo systemctl restart kubelet.service
    # sudo service kubelet status
    # /var/log/pods
    
    Write-Host "Cheat Sheet for journalctl: https://www.cheatography.com/airlove/cheat-sheets/journalctl/"
    # systemctl list-unit-files | grep .service | grep enabled
    # https://askubuntu.com/questions/795226/how-to-list-all-enabled-services-from-systemctl

    # restart VM: az vm restart -g MyResourceGroup -n MyVm
    # list vm sizes available: az vm list-sizes --location "eastus" --query "[].name"
}

function global:RestartDNSPodsIfNeeded() {
    kubectl get pods -l k8s-app=kube-dns -n kube-system -o wide
    Do { $confirmation = Read-Host "Do you want to restart DNS pods? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($confirmation))
    
    if ($confirmation -eq 'y') {
        $failedItems = kubectl get pods -l k8s-app=kube-dns -n kube-system -o jsonpath='{range.items[*]}{.metadata.name}{\"\n\"}{end}'
        ForEach ($line in $failedItems) {
            Write-Host "Deleting pod $line"
            kubectl delete pod $line -n kube-system
        } 
    }             
}
function global:RestartAzureVMsInResourceGroup() {
    # restart VMs
    $AKS_PERS_RESOURCE_GROUP = ReadSecretData -secretname azure-secret -valueName resourcegroup

    if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
        Do { 
            $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group:"
        }
        while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
    }            
    # UpdateOSInVMs -resourceGroup $AKS_PERS_RESOURCE_GROUP
    RestartVMsInResourceGroup -resourceGroup $AKS_PERS_RESOURCE_GROUP
    SetHostFileInVms -resourceGroup $AKS_PERS_RESOURCE_GROUP
    SetupCronTab -resourceGroup $AKS_PERS_RESOURCE_GROUP          
}

function global:TestAzureLoadBalancer() {
    $AKS_PERS_RESOURCE_GROUP = ReadSecretData -secretname azure-secret -valueName resourcegroup

    $urlAndIPForLoadBalancer = $(GetUrlAndIPForLoadBalancer "$AKS_PERS_RESOURCE_GROUP")
    $url = $($urlAndIPForLoadBalancer.Url)
    $ip = $($urlAndIPForLoadBalancer.IP)
                            
    # Invoke-WebRequest -useb -Headers @{"Host" = "nlp.$customerid.healthcatalyst.net"} -Uri http://$loadBalancerIP/nlpweb | Select-Object -Expand Content

    Write-Host "To test out the load balancer, open Git Bash and run:"
    Write-Host "curl --header 'Host: $url' 'http://$ip/dashboard' -k" 
}

function global:OpenTraefikDashboard() {
    $customerid = ReadSecretValue -secretname customerid
    $customerid = $customerid.ToLower().Trim()
    Write-Host "Launching http://$customerid.healthcatalyst.net/internal in the web browser"
    Start-Process -FilePath "http://$customerid.healthcatalyst.net/internal";
    Write-Host "Launching http://$customerid.healthcatalyst.net/external in the web browser"
    Start-Process -FilePath "http://$customerid.healthcatalyst.net/external";
}
function global:CreateKeyVault([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $resourceGroup, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $location) {
    az keyvault create --name "${resourceGroup}-keyvault" --resource-group "$resourceGroup" --location "$location"
}

function global:SaveKeyInVault([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $resourceGroup, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $key, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $value) {
    az keyvault secret set --vault-name "${resourceGroup}-keyvault" --name "$key" --value "$value"
}

function OpenPortInAzure([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $resourceGroup, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][number]$port, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$name, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$protocol, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$type) 
{
    # $sourceTagForAccess = "VirtualNetwork"
    # $networkSecurityGroup="${resourceGroup}-nsg"

    # if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "$name" --nsg-name $networkSecurityGroup --resource-group $resourceGroup))) {
    #     Write-Host "Creating rule: $name"
    #     az network nsg rule create -g $resourceGroup --nsg-name $networkSecurityGroup -n $name --priority 501 `
    #         --source-address-prefixes $sourceTagForAccess --source-port-ranges '*' `
    #         --destination-address-prefixes '*' --destination-port-ranges $port --access Allow `
    #         --protocol $protocol --description "allow HTTPS access from $sourceTagForAccess." `
    #         --query "provisioningState" -o tsv
    # }
    # else {
    #     Write-Host "Updating rule: $name"
    #     az network nsg rule update -g $resourceGroup --nsg-name $networkSecurityGroup -n $name --priority 501 `
    #         --source-address-prefixes $sourceTagForAccess --source-port-ranges '*' `
    #         --destination-address-prefixes '*' --destination-port-ranges $port --access Allow `
    #         --protocol $protocol --description "allow HTTPS access from $sourceTagForAccess." `
    #         --query "provisioningState" -o tsv
    # }    
}

# --------------------
Write-Information -MessageData "end common-azure.ps1 version $versionazurecommon"
