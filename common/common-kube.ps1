# this file contains common functions for kubernetes
$versionkubecommon = "2018.06.05.01"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Information -MessageData "Including common-kube.ps1 version $versionkubecommon"
function global:GetCommonKubeVersion() {
    return $versionkubecommon
}

function WriteToLog($txt) {
    Write-Information -MessageData "$txt"
}

function WriteToConsole($txt) {
    # Write-Information -MessageData "$txt"
    Write-Host "===============================================" -ForegroundColor "Magenta"
    Write-Host "$txt" -ForegroundColor "Magenta"
    Write-Host "===============================================" -ForegroundColor "Magenta"
}

function global:ReadSecretData([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $valueName, [string] $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath="{.data.${valueName}}" -n $namespace --ignore-not-found=true 2> $null

    if (![string]::IsNullOrWhiteSpace($secretbase64)) {
        $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
        return $secretvalue
    }
    
    return "";
}

function global:ReadSecretValue([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [string]$namespace) {
    return ReadSecretData -secretname $secretname -valueName "value" -namespace $namespace
}

function global:ReadSecretPassword([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [string]$namespace) {
    return ReadSecretData -secretname $secretname -valueName "password" -namespace $namespace
}

function global:ReadAllSecretsAsHashTable([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    [hashtable]$Return = @{} 

    $Return.Secrets = @()

    Write-Information -MessageData  "---- $namespace ---"

    $secrets = $(kubectl get secrets -n $namespace -o jsonpath="{.items[?(@.type=='Opaque')].metadata.name}")
    if ($secrets) {
        foreach ($secret in $secrets.Split(" ")) {
            $secretjson = $(kubectl get secret $secret -n $namespace -o json) | ConvertFrom-Json
            foreach ($secretitem in $secretjson.data) {
                $properties = $($secretitem | Get-Member -MemberType NoteProperty)
                $secretlist = @()
                foreach ($property in $properties) {
                    $propertyName = $property.Name
                    Write-Information -MessageData  $propertyName
                    $value = $($secretitem | Select-Object -ExpandProperty $propertyName)
                    $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($value))
                    $secretlist += @{
                        key   = "$propertyName"
                        value = "$secretvalue"    
                    }                        
                }
                $Return.Secrets += @{
                    secretname   = "$secret"
                    namespace    = "$namespace"
                    secretvalues = $secretlist
                }
            }
        }
    }
    return $Return
}

function global:GeneratePassword() {
    $Length = 3
    $set1 = "abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $set2 = "0123456789".ToCharArray()
    $set3 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    $set4 = "!.*@".ToCharArray()        
    $result = ""
    for ($x = 0; $x -lt $Length; $x++) {
        $result += $set1 | Get-Random
        $result += $set2 | Get-Random
        $result += $set3 | Get-Random
        $result += $set4 | Get-Random
    }
    return $result
}

function global:SaveSecretValue([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $valueName, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$value, [string]$namespace) {
    [hashtable]$Return = @{} 

    # secretname must be lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    if (![string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {
        kubectl delete secret $secretname -n $namespace
    }

    kubectl create secret generic $secretname --namespace=$namespace --from-literal=${valueName}=$value

    return $Return
}

function global:SaveMultipleSecretValues([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][array] $secretvalues) 
{
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {
        $command = "kubectl create secret generic $secretname --namespace=$namespace"
        foreach ($secretvalue in $secretvalues) {
            $command = "$command --from-literal=$($secretvalue.secretkey)=$($secretvalue.secretvalue)"
        }
        Invoke-Expression -Command $command
    }
    else {
        Write-Information -MessageData "$secretname secret already set so will reuse it"
    }   

    return $Return
}

function global:AskForPassword ([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [string]$prompt, [string]$namespace) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpassword = Read-Host "$prompt (leave empty for auto-generated)"
            if ($mysqlrootpassword.Length -lt 1) {
                $mysqlrootpassword = GeneratePassword
            }
        }
        while (($mysqlrootpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlrootpassword.Length -lt 8 ))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Information -MessageData "$secretname secret already set so will reuse it"
    }

    return $Return
}

function global:GenerateSecretPassword ([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [string]$namespace) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

        Write-Information -MessageData "$secretname not found so generating it"
        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpassword = GeneratePassword
        }
        while (($mysqlrootpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlrootpassword.Length -lt 8 ))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Information -MessageData "$secretname secret already set so will reuse it"
    }

    return $Return
}

function global:AskForPasswordAnyCharacters ([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [string]$prompt, [string]$namespace, [string]$defaultvalue) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $fullprompt = $prompt
            if ($defaultvalue) {
                $fullprompt = "$prompt (leave empty for default)"
            }
            $mysqlrootpassword = Read-host "$fullprompt"
            if ($mysqlrootpassword.Length -lt 1) {
                $mysqlrootpassword = $defaultvalue
            }
        }
        while (($mysqlrootpassword.Length -lt 8 ) -and (!("$mysqlrootpassword" -eq "$defaultvalue")))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Information -MessageData "$secretname secret already set so will reuse it"
    }

    return $Return
}

function global:AskForSecretValue ([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $prompt, [string]$namespace, [string]$defaultvalue) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

        $certhostname = ""
        Do {
            $certhostname = Read-host "$prompt"
            if (!$certhostname) {
                if ($defaultvalue) {
                    $certhostname = $defaultvalue
                }
            }
        }
        while ($certhostname.Length -lt 1 )
    
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$certhostname
    }
    else {
        Write-Information -MessageData "$secretname secret already set so will reuse it"
    }    
    return $Return
}

function global:ReadYamlAndReplaceTokens([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $templateFile, `
        [Parameter(Mandatory = $true)][ValidateNotNull()][hashtable] $tokens, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][bool] $local) {
    [hashtable]$Return = @{} 
    
    Write-Information -MessageData "Reading from url: ${baseUrl}/${templateFile}"

    if ($baseUrl.StartsWith("http")) { 
        $response = $(Invoke-WebRequest -Uri "${baseUrl}/${templateFile}?f=${randomstring}" -UseBasicParsing -ErrorAction:Stop -ContentType "text/plain; charset=utf-8")
        $content = $response | Select-Object -Expand Content
    }
    else {
        $content = $(Get-Content -Path "$baseUrl/$templateFile")
    }

    $content = $(Merge-Tokens $content $tokens)
    
    $Return.Content = $content
    return $Return
}

function global:ReadYaml([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $templateFile, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][bool] $local) {
    [hashtable]$Return = @{} 
    
    [hashtable]$tokens = @{ 
    }

    $Return.Content = $(ReadYamlAndReplaceTokens -baseUrl $baseUrl -templateFile $templateFile -tokens $tokens -local $local).Content
    return $Return
}

# from https://github.com/majkinetor/posh/blob/master/MM_Network/Stop-ProcessByPort.ps1
function global:Stop-ProcessByPort( [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] [int] $Port ) {    
    [hashtable]$Return = @{} 

    $netstat = netstat.exe -ano | Select-Object -Skip 4
    $p_line = $netstat | Where-Object { $p = ( -split $_ | Select-Object -Index 1) -split ':' | Select-Object -Last 1; $p -eq $Port } | Select-Object -First 1
    if (!$p_line) { Write-Information -MessageData "No process found using port" $Port; return }    
    $p_id = $p_line -split '\s+' | Select-Object -Last 1
    if (!$p_id) { throw "Can't parse process id for port $Port" }
    
    Read-Host "There is another process running on this port.  Click ENTER to open an elevated prompt to stop that process."

    Start-Process powershell -verb RunAs -Wait -ArgumentList "Stop-Process $p_id -Force"

    return $Return
}


function global:CreateNamespaceIfNotExists([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($(kubectl get namespace $namespace --ignore-not-found=true))) {
        Write-Information -MessageData "Creating namespace: $namespace"
        kubectl create namespace $namespace
    }
    return $Return
}


function global:CleanOutNamespace([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    [hashtable]$Return = @{} 

    Write-Information -MessageData "--- Cleaning out any old resources in $namespace ---"

    # note kubectl doesn't like spaces in between commas below
    kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,jobs,cronjobs' --namespace=$namespace --ignore-not-found=true

    # can't delete persistent volume claims since they are not scoped to namespace
    kubectl delete 'pv' -l namespace=$namespace --ignore-not-found=true

    Write-Information -MessageData "Waiting for resources to be deleted"
    $CLEANUP_DONE = "n"
    $counter = 0
    Do {
        $CLEANUP_DONE = $(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,jobs,cronjobs' --namespace=$namespace -o jsonpath="{.items[*].metadata.name}")
        if (![string]::IsNullOrEmpty($CLEANUP_DONE)) {
            $counter++
            Write-Information -MessageData "[$counter] Remaining items: $CLEANUP_DONE"
            Start-Sleep 5
        }
    }
    while ((![string]::IsNullOrEmpty($CLEANUP_DONE)) -and ($counter -lt 12))

    if (![string]::IsNullOrEmpty($CLEANUP_DONE)) {
        Write-Information -MessageData "Deleting pods didn't work so deleting with force"
        kubectl delete --all 'pods' --grace-period=0 --force --namespace=$namespace --ignore-not-found=true
        Write-Information -MessageData "Waiting for resources to be deleted"
        $CLEANUP_DONE = "n"
        $counter = 0
        Do {
            $CLEANUP_DONE = $(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,jobs,cronjobs' --namespace=$namespace -o jsonpath="{.items[*].metadata.name}")
            if (![string]::IsNullOrEmpty($CLEANUP_DONE)) {
                $counter++
                Write-Information -MessageData "[$counter] Remaining items: $CLEANUP_DONE"
                Start-Sleep 5
            }
        }
        while ((![string]::IsNullOrEmpty($CLEANUP_DONE)) -and ($counter -lt 12))
    }
    
    return $Return
}

function global:DeleteAllSecrets([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    [hashtable]$Return = @{} 

    Write-Information -MessageData "--- Deleting all secrets in $namespace ---"
    $secrets = $(kubectl get secrets -n $namespace -o jsonpath="{.items[?(@.type=='Opaque')].metadata.name}")
    foreach ($secret in $secrets.Split(" ")) {
        Write-Information -MessageData "deleting secret: $secret"
        kubectl delete secret $secret -n $namespace
    }

    return $Return
}

function global:SwitchToKubCluster([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $folderToUse) {

    [hashtable]$Return = @{} 

    $fileToUse = "${folderToUse}\temp\.kube\config"

    Write-Information -MessageData "Checking if file exists: $fileToUse"

    if (Test-Path -Path $fileToUse) {
        $userKubeConfigFolder = "${env:userprofile}\.kube"
        If (!(Test-Path $userKubeConfigFolder)) {
            Write-Information -MessageData "Creating $userKubeConfigFolder"
            New-Item -ItemType Directory -Force -Path "$userKubeConfigFolder"
        }            

        $destinationFile = "${userKubeConfigFolder}\config"
        Write-Information -MessageData "Copying $fileToUse to $destinationFile"
        Copy-Item -Path "$fileToUse" -Destination "$destinationFile"
        # set environment variable KUBECONFIG to point to this location
        $env:KUBECONFIG = "$destinationFile"
        [Environment]::SetEnvironmentVariable("KUBECONFIG", "$destinationFile", [EnvironmentVariableTarget]::User)
        Write-Information -MessageData "Current cluster: $(kubectl config current-context)"    
    }
    else {
        Write-Error "$fileToUse not found"
    }

    return $Return
}
function global:CleanKubConfig() {
    [hashtable]$Return = @{} 

    Write-Information -MessageData "Clearing out kube config"
    $userKubeConfigFolder = "$env:userprofile\.kube"
    $destinationFile = "${userKubeConfigFolder}\config"
    Remove-Item -Path "$destinationFile" -Force
    # set environment variable KUBECONFIG to point to this location
    $env:KUBECONFIG = ""
    [Environment]::SetEnvironmentVariable("KUBECONFIG", "", [EnvironmentVariableTarget]::User)

    return $Return
}

function global:DeployYamlFile([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $templateFile, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, `
        [Parameter(Mandatory = $true)][ValidateNotNull()][hashtable] $tokens, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][bool] $local) {
    # $resources can be null
    [hashtable]$Return = @{} 

    $(ReadYamlAndReplaceTokens -baseUrl $baseUrl -templateFile $templateFile -local $local -tokens $tokens).Content | kubectl apply -f -
    $result = $LASTEXITCODE
    if ($result -ne 0) {
        throw "Error applying kubernetes template: $templateFile"
    }
    return $Return
}

function global:DeployYamlFiles([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $appfolder, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $folder, `
        [Parameter(Mandatory = $true)][ValidateNotNull()][hashtable] $tokens, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][bool] $local, `
        $resources) {
    # $resources can be null
    [hashtable]$Return = @{} 

    if ($resources) {
        Write-Information -MessageData "-- Deploying $folder --"
        foreach ($file in $resources) {
            DeployYamlFile -baseUrl $baseUrl -templateFile "${appfolder}/${folder}/${file}" -tokens $tokens -local $local
        }
    }
    return $Return
}
function global:LoadStack([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $appfolder, `
        [Parameter(Mandatory = $true)][ValidateNotNull()] $config,
    $isAzure, `
        [string]$externalIp, `
        [string]$internalIp, `
        [string]$externalSubnetName, `
        [string]$internalSubnetName, `
        [Parameter(Mandatory = $true)][ValidateNotNull()][bool] $local) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($(kubectl get namespace $namespace --ignore-not-found=true))) {
        Write-Information -MessageData "namespace $namespace does not exist so creating it"
        kubectl create namespace $namespace
    }
    
    Write-Information -MessageData "Installing stack $($config.name) version $($config.version) from $configpath"

    foreach ($secret in $($config.secrets.password)) {
        GenerateSecretPassword -secretname "$secret" -namespace "$namespace"
    }
    foreach ($secret in $($config.secrets.value)) {
        # AskForSecretValue -secretname "$secret" -prompt "Client Certificate hostname" -namespace "$namespace"        
        if ($secret -is [String]) {
            AskForSecretValue -secretname "$secret" -prompt "Client Certificate hostname" -namespace "$namespace"
        }
        else {
            $sourceSecretName = $($secret.valueFromSecret.name)
            $sourceSecretNamespace = $($secret.valueFromSecret.namespace)
            $value = ReadSecretValue -secretname $sourceSecretName -namespace $sourceSecretNamespace
            Write-Information -MessageData "Setting secret [$($secret.name)] to secret [$sourceSecretName] in namespace [$sourceSecretNamespace] with value [$value]"
            SaveSecretValue -secretname "$($secret.name)" -valueName "value" -value $value -namespace "$namespace"
        }
    }
   
    if ($namespace -ne "kube-system") {
        CleanOutNamespace -namespace $namespace
    }
    
    $customerid = ReadSecretValue -secretname customerid
    $customerid = $customerid.ToLower().Trim()
    Write-Information -MessageData "Customer ID: $customerid"

    Write-Information -MessageData "EXTERNALSUBNET: $externalSubnetName"
    Write-Information -MessageData "EXTERNALIP: $externalIp"
    Write-Information -MessageData "INTERNALSUBNET: $internalSubnetName"
    Write-Information -MessageData "INTERNALIP: $internalIp"

    $runOnMaster = $false

    [hashtable]$tokens = @{ 
        "CUSTOMERID"         = $customerid;
        "EXTERNALSUBNET"     = "$externalSubnetName";
        "EXTERNALIP"         = "$externalIp";
        "#REPLACE-RUNMASTER" = "$runOnMaster";
        "INTERNALSUBNET"     = "$internalSubnetName";
        "INTERNALIP"         = "$internalIp";
    }

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "dns" -tokens $tokens -resources $($config.resources.dns) -local $local

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "configmaps" -tokens $tokens -resources $($config.resources.configmaps) -local $local

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "roles" -tokens $tokens -resources $($config.resources.roles) -local $local
    
    if ($isAzure) {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "volumes/azure" -tokens $tokens -resources $($config.resources.volumes.azure) -local $local
    }
    else {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "volumes/onprem" -tokens $tokens -resources $($config.resources.volumes.onprem) -local $local
    }

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "volumeclaims" -tokens $tokens -resources $($config.resources.volumeclaims) -local $local
    
    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "pods" -tokens $tokens -resources $($config.resources.pods) -local $local

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "services/cluster" -tokens $tokens -resources $($config.resources.services.cluster) -local $local

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "services/external" -tokens $tokens -resources $($config.resources.services.external) -local $local
    
    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "ingress/http" -tokens $tokens -resources $($config.resources.ingress.http) -local $local

    if ($isAzure) {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "ingress/tcp/azure" -tokens $tokens -resources $($config.resources.ingress.tcp.azure) -local $local
    }
    else {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "ingress/tcp/onprem" -tokens $tokens -resources $($config.resources.ingress.tcp.onprem) -local $local
    }

    if ($(HasProperty -object $($config.resources.ingress) "jobs")) {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "jobs" -tokens $tokens -resources $($config.resources.ingress.jobs) -local $local
    }

    # DeploySimpleServices -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -tokens $tokens -resources $($config.resources.ingress.simpleservices)

    WaitForPodsInNamespace -namespace $namespace -interval 5
    return $Return
}

function HasProperty([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] $object, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$propertyName) {
    $propertyName -in $object.PSobject.Properties.Name
}

function global:WaitForPodsInNamespace([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, $interval) {
    [hashtable]$Return = @{} 

    $pods = $(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    $waitingonPod = "n"

    $counter = 0
    Do {
        $waitingonPod = ""
        Write-Information -MessageData "---- waiting until all pods are running in namespace $namespace ---"

        Start-Sleep -Seconds $interval
        $counter++
        $pods = $(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')

        if (!$pods) {
            throw "No pods were found in namespace $namespace"
        }

        foreach ($pod in $pods.Split(" ")) {
            $podstatus = $(kubectl get pods $pod -n $namespace -o jsonpath='{.status.phase}')
            if ($podstatus -eq "Running") {
                # nothing to do
            }
            elseif ($podstatus -eq "Pending") {
                # Write-Information -MessageData "${pod}: $podstatus"
                $containerReady = $(kubectl get pods $pod -n $namespace -o jsonpath="{.status.containerStatuses[0].ready}")
                if ($containerReady -ne "true" ) {
                    $containerStatus = $(kubectl get pods $pod -n $namespace -o jsonpath="{.status.containerStatuses[0].state.waiting.reason}")
                    if (![string]::IsNullOrEmpty(($containerStatus))) {
                        $waitingonPod = "${waitingonPod}${pod}($containerStatus);"    
                    }
                    else {
                        $waitingonPod = "${waitingonPod}${pod}(container);"                        
                    }
                    # Write-Information -MessageData "container in $pod is not ready yet: $containerReady"
                }
            }
            else {
                $waitingonPod = "${waitingonPod}${pod}($podstatus);" 
            }
        }
            
        Write-Information -MessageData "[$counter] $waitingonPod"
    }
    while (![string]::IsNullOrEmpty($waitingonPod) -and ($counter -lt 30) )

    kubectl get pods -n $namespace -o wide

    if ($counter -gt 29) {
        Write-Information -MessageData "--- warnings in kubenetes event log ---"
        kubectl get events -n $namespace | grep "Warning" | tail    
    } 
    return $Return    
}

function global:DeploySimpleService([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $appfolder, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $customerid, $service) {
    [hashtable]$Return = @{} 

    Write-Information -MessageData "Deploying simpleservice: $($service.name)"

    $servicepublic = "$($service.name)-service"

    $tokens = @{
        name          = $service.name
        namespace     = "$namespace"
        image         = "$($service.image)"
        servicepublic = "$servicepublic"
    }

    Write-Information -MessageData "Creating pods for simpleservice"
    # replace env section
    # populate ports

    $templatefile = "$baseUrl\templates\pods\template.json"
    $template = $(Get-Content -Raw -Path $templatefile)
    $jsontext = $(Merge-Tokens $template $tokens)
    $json = $jsontext | ConvertFrom-Json

    $container = $json.spec.template.spec.containers[0]
    # replace env section
    $container.env = $service.env
    # populate ports
    foreach ($port in $($service.ports)) {
        $properties = @{
            'containerPort' = $port.containerPort;
            'name'          = $port.name
        }
        $object = New-Object –TypeNamePSObject –Prop $properties
        $container.ports += $object
    }
    Write-Information -MessageData "--- deployment ---"
    Write-Information -MessageData $json            

    Write-Information -MessageData "Creating services for simpleservice"
    $templatefile = "$baseUrl\templates\services\cluster\template.json"
    $template = $(Get-Content -Raw -Path $templatefile)
    $jsontext = $(Merge-Tokens $template $tokens)
    $json = $jsontext | ConvertFrom-Json

    foreach ($port in $($service.ports)) {
        $portspec = @{
            port       = $port.port
            targetPort = $port.targetPort
            protocol   = "TCP"
        }
        $json.ports += $portspec
    }
    Write-Information -MessageData "--- cluster service ---"
    Write-Information -MessageData $json            

    Write-Information -MessageData "Creating ingress for simpleservice"
    $templatefile = "$baseUrl\templates\ingress\http\template.path.json"
    $template = $(Get-Content -Raw -Path $templatefile)
    $jsontext = $(Merge-Tokens $template $tokens)
    $json = $jsontext | ConvertFrom-Json

    foreach ($port in $($service.ports)) {
        $pathspec = @{
            path    = $($port.http.path)
            backend = @{
                serviceName = "$servicepublic"
            }
        }
        $json.spec.rules[0].http.paths += $pathspec

        # $json.ports.add $portspec
    }

    Write-Information -MessageData "Creating Persistent Volumes for simple service"

    Write-Information -MessageData "Creating Volume Claims for simple service"

    return $Return
}

function global:DeploySimpleServices([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $baseUrl, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $appfolder, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $customerid, `
        $services) {
    [hashtable]$Return = @{} 

    if ($services) {
        Write-Information -MessageData "-- Deploying simpleservices --"
        foreach ($service in $services) {
            DeploySimpleService -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -customerid $customerid -service $service
        }
    }
    return $Return
}

function global:LoadLoadBalancerStack([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] [string]$baseUrl, [int]$ssl, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] [string]$ingressInternalType, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] [string]$ingressExternalType, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()] [string]$customerid, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][bool] $isOnPrem, `
        [string]$externalIp, `
        [string]$internalIp, `
        [string]$externalSubnetName, `
        [string]$internalSubnetName, `
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][bool]$local) {
    [hashtable]$Return = @{} 

    # delete existing containers
    kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

    # set Google DNS servers to resolve external  urls
    # http://blog.kubernetes.io/2017/04/configuring-private-dns-zones-upstream-nameservers-kubernetes.html
    kubectl delete -f "$baseUrl/loadbalancer/dns/upstream.yaml" --ignore-not-found=true
    Start-Sleep -Seconds 10
    $tokens = @{}
    DeployYamlFile -baseUrl $baseUrl -templateFile "loadbalancer/dns/upstream.yaml" -tokens $tokens -local $local
    
    # to debug dns: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#inheriting-dns-from-the-node

    kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

    Write-Information -MessageData "baseUrl: $baseUrl"

    # setting up traefik
    # https://github.com/containous/traefik/blob/master/docs/user-guide/kubernetes.md

    $runOnMaster = ""

    # $traefiklabels = "external,internal"
    Write-Information -MessageData "LoadLoadBalancerStack"
          
    Write-Information -MessageData "Customer ID: $customerid"

    Write-Information -MessageData "EXTERNALSUBNET: $externalSubnetName"
    Write-Information -MessageData "EXTERNALIP: $externalIp"
    Write-Information -MessageData "INTERNALSUBNET: $internalSubnetName"
    Write-Information -MessageData "INTERNALIP: $internalIp"
    
    [hashtable]$tokens = @{ 
        "CUSTOMERID"         = $customerid;
        "EXTERNALSUBNET"     = "$externalSubnetName";
        "EXTERNALIP"         = "$externalIp";
        "#REPLACE-RUNMASTER" = "$runOnMaster";
        "INTERNALSUBNET"     = "$internalSubnetName";
        "INTERNALIP"         = "$internalIp";
    }    

    $namespace = "kube-system"
    $appfolder = "loadbalancer"
    Write-Information -MessageData "Deploying configmaps"
    $folder = "configmaps"
    if ($ssl) {
        $files = "config.ssl.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }
    else {
        $files = "config.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }

    Write-Information -MessageData "Deploying pods"
    $folder = "pods"

    if ($ingressExternalType -eq "onprem" ) {
        $files = "traefik-onprem.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }
    elseif ($ingressInternalType -eq "public" ) {
        $files = "traefik-azure.both.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }
    else {
        if ($ssl) {
            $files = "traefik-azure.external.ssl.yaml traefik-azure.internal.ssl.yaml"
            DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
        }
        else {
            $files = "traefik-azure.external.yaml traefik-azure.internal.yaml"
            DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
        }    
    }

    Write-Information -MessageData "Deploying services"

    # Write-Information -MessageData "Deploying http ingress"
    # $folder = "ingress/http"
    # $files = "apidashboard.yaml"
    # DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ")

    $folder = "services/external"

    if ($ingressExternalType -eq "onprem" ) {
        Write-Information -MessageData "Setting up external load balancer"
        $files = "loadbalancer.onprem.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }    
    elseif ("$ingressExternalType" -ne "vnetonly") {
        Write-Information -MessageData "Setting up a public load balancer"

        Write-Information -MessageData "Using External IP: [$externalIp]"

        Write-Information -MessageData "Setting up external load balancer"
        $files = "loadbalancer.external.public.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }
    else {
        Write-Information -MessageData "Setting up an external load balancer"
        $files = "loadbalancer.external.vnetonly.yaml"
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local
    }


    if ($ingressExternalType -eq "onprem" ) {
    }
    elseif ("$ingressInternalType" -eq "public") {
        Write-Information -MessageData "Setting up an internal load balancer"
        $files = "loadbalancer.internal.public.yaml"
    }
    else {
        Write-Information -MessageData "Setting up an internal load balancer"
        Write-Information -MessageData "Using Internal IP: [$internalIp]"
        $files = "loadbalancer.internal.vnetonly.yaml"
    }
    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder $folder -tokens $tokens -resources $files.Split(" ") -local $local

    InstallStack -baseUrl $baseUrl -namespace $namespace -appfolder $appfolder `
        -externalSubnetName "$externalSubnetName" -externalIp "$externalip" `
        -internalSubnetName "$internalSubnetName" -internalIp "$internalIp" `
        -local $local

    WaitForPodsInNamespace -namespace kube-system -interval 5

    return $Return
}
# from http://www.bricelam.net/2012/09/simple-template-engine-for-powershell.html
# Merge-Tokens 'Hello, $target$! My name is $self$.' @{
#    Target = 'World'
#    Self = 'Brice'
#}
function Merge-Tokens($template, $tokens) {
    return [regex]::Replace(
        $template,
        '\$(?<tokenName>\w+)\$',
        {
            param($match)

            $tokenName = $match.Groups['tokenName'].Value

            return $tokens[$tokenName]
        })
}

function global:FixLabelOnMaster() {
    # for some reaosn ACS doesn't set this label on the master correctly and we need it to target pods to the master
    Write-Information -MessageData "Looking for node with label [kubernetes.io/role=master]"
    $masternodename = $(kubectl get nodes -l kubernetes.io/role=master -o jsonpath="{.items[0].metadata.name}")
    if (![string]::IsNullOrEmpty($masternodename)) {
        Write-Information -MessageData "Setting label [node-role.kubernetes.io/master] on node [$masternodename]"
        kubectl label nodes $masternodename node-role.kubernetes.io/master=""
    }
    else {
        Write-Information -MessageData "No node found with label [kubernetes.io/role=master]"        
    }
}

function global:TestFunction() {
    param( [string]$namespace, [string]$size)     

    [hashtable]$Return = @{} 

    Write-Information -MessageData "namespace: $namespace"
    Write-Information -MessageData "size: $size"

    $Return.Namespace = "$namespace $size"
    return $Return    
}

function ShowStatusOfAllPodsInNameSpace([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    Write-Information -MessageData "showing status of pods in $namespace"
    $pods = $(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    foreach ($pod in $pods.Split(" ")) {
        Write-Information -MessageData "=============== Describe Pod: $pod ================="
        kubectl describe pods $pod -n $namespace
    }
}
function ShowLogsOfAllPodsInNameSpace([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    Write-Information -MessageData "showing logs (last 30 lines) in $namespace"
    $pods = $(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    foreach ($pod in $pods.Split(" ")) {
        Write-Information -MessageData "=============== Describe Pod: $pod ================="
        kubectl logs --tail=30 $pod -n $namespace
    }   
}

function ShowStatusOfCluster() {
    Write-Information -MessageData "Current cluster: $(kubectl config current-context)"
    kubectl version --short
    kubectl get "deployments,pods,services,nodes,ingress" --namespace=kube-system -o wide    
}

function ShowNodes() {
    Write-Host "Current cluster: $(kubectl config current-context)"
    kubectl version --short
    kubectl get "nodes" -o wide
}

function ShowLoadBalancerLogs() {
    # kubectl logs --namespace=kube-system -l k8s-app=traefik-ingress-lb-onprem --tail=100
    $pods = $(kubectl get pods -l k8s-traefik=traefik -n kube-system -o jsonpath='{.items[*].metadata.name}')
    foreach ($pod in $pods.Split(" ")) {
        Write-Host "=============== Pod: $pod ================="
        kubectl logs --tail=20 $pod -n kube-system 
    }
}

function GenerateKubeConfigFile() {
    $user = "api-dashboard-user"
    # https://kubernetes.io/docs/getting-started-guides/scratch/#preparing-credentials
    # https://stackoverflow.com/questions/47770676/how-to-create-a-kubectl-config-file-for-serviceaccount
    $secretname = $(kubectl -n kube-system get secret | grep $user | awk '{print $1}')
    $ca = $(kubectl get secret $secretname -n kube-system -o jsonpath='{.data.ca\.crt}') # ca doesn't use base64 encoding
    $token = $(ReadSecretData "$secretname" "token" "kube-system")
    $namespace = $(ReadSecretData "$secretname" "namespace" "kube-system")
    $server = $(ReadSecretValue -secretname "dnshostname" -namespace "default")
    $serverurl = "https://${server}:6443"

    # the multiline string below HAS to start at the beginning of the line per powershell
    # https://www.kongsli.net/2012/05/03/powershell-gotchas-getting-multiline-string-literals-correct/
    $kubeconfig =
    @"
apiVersion: v1
kind: Config
clusters:
- name: ${server}
  cluster:
    certificate-authority-data: ${ca}
    server: ${serverurl}
contexts:
- name: default-context
  context:
    cluster: ${server}
    namespace: ${namespace}
    user: ${user}
current-context: default-context
users:
- name: ${user}
  user:
    token: ${token}
"@

    Write-Information -MessageData "------ CUT HERE -----"
    Write-Information -MessageData $kubeconfig
    Write-Information -MessageData "------ END CUT HERE ---"
}

function troubleshootIngress([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    $ingresses = $(kubectl get ingress -n $namespace -o jsonpath='{.items[*].metadata.name}')
    foreach ($ingress in $ingresses.Split(" ")) {
        $ingressPath = $(kubectl get ing $ingress -n $namespace -o jsonpath="{.spec.rules[].http.paths[].path}")
        $ingressHost = $(kubectl get ing $ingress -n $namespace -o jsonpath="{.spec.rules[].host}")
        $ingressRuleType = $(kubectl get ing $ingress -n $namespace -o jsonpath="{.metadata.annotations.traefik\.frontend\.rule\.type}")
        $ingressType = $(kubectl get ing $ingress -n $namespace -o jsonpath="{.metadata.labels.expose}")
        Write-Host "=============== Ingress: $ingress ================="
        Write-Host "Ingress Path: $ingressPath"
        Write-Host "Ingress Host: $ingressHost"
        Write-Host "Ingress Type: $ingressType"
        Write-Host "Ingress Rule Type: $ingressRuleType"
        $ingressServiceName = $(kubectl get ing $ingress -n $namespace -o jsonpath="{.spec.rules[].http.paths[].backend.serviceName}")
        $ingressServicePort = $(kubectl get ing $ingress -n $namespace -o jsonpath="{.spec.rules[].http.paths[].backend.servicePort}")
        Write-Host "Service: $ingressServiceName port: $ingressServicePort"
        $servicePort = $(kubectl get svc $ingressServiceName -n $namespace -o jsonpath="{.spec.ports[].port}")
        $targetPort = $(kubectl get svc $ingressServiceName -n $namespace -o jsonpath="{.spec.ports[].targetPort}")
        Write-Host "Service Port: $servicePort target Port: $targetPort"
        $servicePodSelectorMap = $(kubectl get svc $ingressServiceName -n $namespace -o jsonpath="{.spec.selector}")
        $servicePodSelectors = $servicePodSelectorMap.Replace("map[", "").Replace("]", "").Split(" ")
        $servicePodSelectorsList = ""
        foreach ($servicePodSelector in $servicePodSelectors) {
            $servicePodSelectorItems = $servicePodSelector.Split(":")
            $servicePodSelectorKey = $($servicePodSelectorItems[0])
            $servicePodSelectorValue = $($servicePodSelectorItems[1])
            $servicePodSelectorsList += " -l ${servicePodSelectorKey}=${servicePodSelectorValue}"
        }
        Write-Host "Pod Selector: $servicePodSelectorsList"
        $pod = $(Invoke-Expression("kubectl get pod $servicePodSelectorsList -n $namespace -o jsonpath='{.items[*].metadata.name}'"))
        Write-Host "Pod name: $pod"
        $podstatus = $(kubectl get pod $pod -n $namespace -o jsonpath="{.status.phase}")
        Write-Host "Pod status: $podstatus"
        $containerImage = $(kubectl get pod $pod -n $namespace -o jsonpath="{.spec.containers[0].image}")
        Write-Host "Container image: $containerImage"
        $containerPort = $(kubectl get pod $pod -n $namespace -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
        Write-Host "Container Port: $containerPort"
    }   
}

function DeleteAllPodsInNamespace([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    kubectl delete --all 'pods' --namespace=$namespace --ignore-not-found=true
}

function ShowSSHCommandsToContainers([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace) {
    $pods = $(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    foreach ($pod in $pods.Split(" ")) {
        Write-Host "kubectl exec -it $pod -n $namespace -- sh"
    }

}

function global:WriteSecretPasswordToOutput([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname) {
    $secretvalue = $(ReadSecretPassword -secretname $secretname -namespace $namespace)
    Write-Host "$secretname = $secretvalue"
    # Write-Host "To recreate the secret:"
    # Write-Host "kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$secretvalue"
}
function global:WriteSecretValueToOutput([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $namespace, [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $secretname) {
    $secretvalue = $(ReadSecretValue -secretname $secretname -namespace $namespace)
    Write-Host "$secretname = $secretvalue"
    # Write-Host "To recreate the secret:"
    # Write-Host "kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$secretvalue"
}

function global:RunRealtimeTester([ValidateNotNullOrEmpty()][string] $baseUrl) {
    # show commands to download the tester and run it passing in certhostname and password
    $certhostname = $(ReadSecretValue certhostname $namespace)
    $certpassword = $(ReadSecretPassword certpassword $namespace)

    Write-Host "Run on your client machine in a PowerShell window:"
    Write-Host "curl -useb $baseUrl/realtime/realtimetester.ps1 | iex $certhostname $certpassword"
}


# --------------------
Write-Information -MessageData "end common-kube.ps1 version $versionkubecommon"