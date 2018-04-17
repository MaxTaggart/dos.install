# this file contains common functions for kubernetes
$versionkubecommon = "2018.04.16.02"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Information -MessageData "Including common-kube.ps1 version $versionkubecommon"
function global:GetCommonKubeVersion() {
    return $versionkubecommon
}

function global:ReadSecretValue([ValidateNotNullOrEmpty()] $secretname, [ValidateNotNullOrEmpty()] $valueName, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath="{.data.${valueName}}" -n $namespace --ignore-not-found=true 2> $null

    if (![string]::IsNullOrWhiteSpace($secretbase64)) {
        $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
        return $secretvalue
    }
    
    return "";
}

function global:ReadSecret([ValidateNotNullOrEmpty()] $secretname, $namespace) {
    return ReadSecretValue -secretname $secretname -valueName "value" -namespace $namespace
}

function global:ReadSecretPassword([ValidateNotNullOrEmpty()] $secretname, $namespace) {
    return ReadSecretValue -secretname $secretname -valueName "password" -namespace $namespace
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

function global:SaveSecretValue([ValidateNotNullOrEmpty()] $secretname, [ValidateNotNullOrEmpty()] $valueName, $value, $namespace) {
    [hashtable]$Return = @{} 

    # secretname must be lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    if (![string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {
        kubectl delete secret $secretname -n $namespace
    }

    kubectl create secret generic $secretname --namespace=$namespace --from-literal=${valueName}=$value

    return $Return
}

function global:AskForPassword ([ValidateNotNullOrEmpty()] $secretname, $prompt, $namespace) {
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

function global:GenerateSecretPassword ([ValidateNotNullOrEmpty()] $secretname, $namespace) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

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

function global:AskForPasswordAnyCharacters ([ValidateNotNullOrEmpty()] $secretname, $prompt, $namespace, $defaultvalue) {
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

function global:AskForSecretValue ([ValidateNotNullOrEmpty()] $secretname, $prompt, $namespace) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

        $certhostname = ""
        Do {
            $certhostname = Read-host "$prompt"
        }
        while ($certhostname.Length -lt 1 )
    
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$certhostname
    }
    else {
        Write-Information -MessageData "$secretname secret already set so will reuse it"
    }    
    return $Return
}

function global:ReadYamlAndReplaceCustomer([ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $templateFile, $customerid ) {
    [hashtable]$Return = @{} 
    
    Write-Information -MessageData "Reading from url: ${baseUrl}/${templateFile}"

    if ($baseUrl.StartsWith("http")) { 
        $response = $(Invoke-WebRequest -Uri "${baseUrl}/${templateFile}?f=${randomstring}" -UseBasicParsing -ErrorAction:Stop -ContentType "text/plain; charset=utf-8")
        $content = $response | Select-Object -Expand Content | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"}
    }
    else {
        $content=$(Get-Content -Path "$baseUrl/$templateFile" `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"})
    }

    $Return.Content = $content
    return $Return
}

# $files is a list of files separated by spaces
function global:DownloadAndDeployYamlFiles([ValidateNotNullOrEmpty()] $folder, [ValidateNotNullOrEmpty()] $files, [ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $customerid, $public_ip ) {
    [hashtable]$Return = @{} 

    foreach ($file in $files.Split(" ")) { 
        if ([string]::IsNullOrEmpty($public_ip)) {
            $(ReadYamlAndReplaceCustomer -baseUrl $baseUrl -templateFile "${folder}/${file}" -customerid $customerid).Content `
                | kubectl apply -f -
        }
        else {
            $(ReadYamlAndReplaceCustomer -baseUrl $baseUrl -templateFile "${folder}/${file}" -customerid $customerid).Content `
                | Foreach-Object {$_ -replace 'PUBLICIP', "$publicip"} `
                | kubectl apply -f -
        }
    }

    return $Return
}

# from https://github.com/majkinetor/posh/blob/master/MM_Network/Stop-ProcessByPort.ps1
function global:Stop-ProcessByPort( [ValidateNotNullOrEmpty()] [int] $Port ) {    
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


function global:CreateNamespaceIfNotExists([ValidateNotNullOrEmpty()] $namespace) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($(kubectl get namespace $namespace --ignore-not-found=true))) {
        Write-Information -MessageData "Creating namespace: $namespace"
        kubectl create namespace $namespace
    }
    return $Return
}


function global:CleanOutNamespace([ValidateNotNullOrEmpty()] $namespace) {
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

function global:DeleteAllSecrets([ValidateNotNullOrEmpty()] $namespace) {
    [hashtable]$Return = @{} 

    Write-Information -MessageData "--- Deleting all secrets in $namespace ---"
    $secrets = $(kubectl get secrets -n $namespace -o jsonpath="{.items[?(@.type=='Opaque')].metadata.name}")
    foreach ($secret in $secrets.Split(" ")) {
        Write-Information -MessageData "deleting secret: $secret"
        kubectl delete secret $secret -n $namespace
    }

    return $Return
}

function global:SwitchToKubCluster([ValidateNotNullOrEmpty()] $folderToUse) {

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

function global:CleanSecrets([ValidateNotNullOrEmpty()] $namespace) {
    [hashtable]$Return = @{} 

    kubectl delete secret mysqlrootpassword -n $namespace --ignore-not-found=true
    kubectl delete secret mysqlpassword -n $namespace --ignore-not-found=true
    kubectl delete secret certhostname -n $namespace --ignore-not-found=true
    kubectl delete secret certpassword -n $namespace --ignore-not-found=true
    kubectl delete secret rabbitmqmgmtuipassword -n $namespace --ignore-not-found=true    

    return $Return
}

function global:DeployYamlFiles([ValidateNotNullOrEmpty()] $namespace, [ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $appfolder, [ValidateNotNullOrEmpty()] $folder, [ValidateNotNullOrEmpty()] $customerid, $resources) {
    [hashtable]$Return = @{} 

    if ($resources) {
        Write-Information -MessageData "-- Deploying $folder --"
        foreach ($file in $resources) {
            $(ReadYamlAndReplaceCustomer -baseUrl $baseUrl -templateFile "${appfolder}/${folder}/${file}" -customerid $customerid).Content | kubectl apply -f -
        }
    }
    return $Return
}
function global:LoadStack([ValidateNotNullOrEmpty()] $namespace, [ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $appfolder, $isAzure) {
    [hashtable]$Return = @{} 

    if ([string]::IsNullOrWhiteSpace($(kubectl get namespace $namespace --ignore-not-found=true))) {
        Write-Information -MessageData "namespace $namespace does not exist so creating it"
        kubectl create namespace $namespace
    }
    
    $configpath = "$baseUrl/${appfolder}/index.json"
    $config = $(Invoke-WebRequest -useb $configpath | ConvertFrom-Json)

    # $configpath="./$appfolder/index.json"
    # $config = $(Get-Content "$configpath" -Raw | ConvertFrom-Json)

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
            $value = ReadSecret -secretname $sourceSecretName -namespace $sourceSecretNamespace
            Write-Information -MessageData "Setting secret [$($secret.name)] to secret [$sourceSecretName] in namespace [$sourceSecretNamespace] with value [$value]"
            SaveSecretValue -secretname "$($secret.name)" -valueName "value" -value $value -namespace "$namespace"
        }
    }
   
    if ($namespace -ne "kube-system") {
        CleanOutNamespace -namespace $namespace
    }
    
    $customerid = ReadSecret -secretname customerid
    $customerid = $customerid.ToLower().Trim()
    Write-Information -MessageData "Customer ID: $customerid"

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "dns" -customerid $customerid -resources $($config.resources.dns)

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "configmaps" -customerid $customerid -resources $($config.resources.configmaps)

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "roles" -customerid $customerid -resources $($config.resources.roles)
    
    if ($isAzure) {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "volumes/azure" -customerid $customerid -resources $($config.resources.volumes.azure)
    }
    else {
        DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "volumes/onprem" -customerid $customerid -resources $($config.resources.volumes.onprem)
    }

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "volumeclaims" -customerid $customerid -resources $($config.resources.volumeclaims)
    
    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "pods" -customerid $customerid -resources $($config.resources.pods)

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "services/cluster" -customerid $customerid -resources $($config.resources.services.cluster)

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "services/external" -customerid $customerid -resources $($config.resources.services.external)
    
    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "ingress/http" -customerid $customerid -resources $($config.resources.ingress.http)

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "ingress/tcp" -customerid $customerid -resources $($config.resources.ingress.tcp)

    DeployYamlFiles -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -folder "jobs" -customerid $customerid -resources $($config.resources.ingress.jobs)
    
    # DeploySimpleServices -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -customerid $customerid -resources $($config.resources.ingress.simpleservices)

    WaitForPodsInNamespace -namespace $namespace -interval 5
    return $Return
}

function global:WaitForPodsInNamespace([ValidateNotNullOrEmpty()] $namespace, $interval){
    [hashtable]$Return = @{} 

    $pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    $waitingonPod="n"

    $counter = 0
    Do {
        $waitingonPod=""
        Write-Information -MessageData "---- waiting until all pods are running in namespace $namespace ---"

        Start-Sleep -Seconds $interval
        $counter++
        $pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')

        foreach ($pod in $pods.Split(" ")) {
            $podstatus=$(kubectl get pods $pod -n $namespace -o jsonpath='{.status.phase}')
            if($podstatus -eq "Running"){
                # nothing to do
            }
            elseif($podstatus -eq "Pending"){
                # Write-Information -MessageData "${pod}: $podstatus"
                $containerReady=$(kubectl get pods $pod -n $namespace -o jsonpath="{.status.containerStatuses[0].ready}")
                if($containerReady -ne "true" ){
                    $containerStatus=$(kubectl get pods $pod -n $namespace -o jsonpath="{.status.containerStatuses[0].waiting.reason}")
                    if(![string]::IsNullOrEmpty(($containerStatus))){
                        $waitingonPod="${waitingonPod}${pod}($containerStatus);"    
                    }
                    else {
                        $waitingonPod="${waitingonPod}${pod}(container);"                        
                    }
                    # Write-Information -MessageData "container in $pod is not ready yet: $containerReady"
                }
            }
            else {
                $waitingonPod="${waitingonPod}${pod}($podstatus);" 
            }
        }
            
        Write-Information -MessageData "[$counter] $waitingonPod"
    }
    while (![string]::IsNullOrEmpty($waitingonPod) -and ($counter -lt 30) )

    kubectl get pods -n $namespace -o wide
    return $Return    
}

function global:DeploySimpleService([ValidateNotNullOrEmpty()] $namespace, [ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $appfolder, [ValidateNotNullOrEmpty()] $customerid, $service) {
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

function global:DeploySimpleServices([ValidateNotNullOrEmpty()] $namespace, [ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $appfolder, [ValidateNotNullOrEmpty()] $customerid, $services) {
    [hashtable]$Return = @{} 

    if ($services) {
        Write-Information -MessageData "-- Deploying simpleservices --"
        foreach ($service in $services) {
            DeploySimpleService -namespace $namespace -baseUrl $baseUrl -appfolder $appfolder -customerid $customerid -service $service
        }
    }
    return $Return
}

function global:LoadLoadBalancerStack([ValidateNotNullOrEmpty()] [string]$baseUrl, [int]$ssl, [ValidateNotNullOrEmpty()] [string]$ingressInternal, [ValidateNotNullOrEmpty()] [string]$ingressExternal, [ValidateNotNullOrEmpty()] [string]$customerid, [string]$publicIp) {
    [hashtable]$Return = @{} 

    # delete existing containers
    kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

    # set Google DNS servers to resolve external  urls
    # http://blog.kubernetes.io/2017/04/configuring-private-dns-zones-upstream-nameservers-kubernetes.html
    kubectl delete -f "$baseUrl/loadbalancer/dns/upstream.yaml" --ignore-not-found=true
    Start-Sleep -Seconds 10
    kubectl create -f "$baseUrl/loadbalancer/dns/upstream.yaml"
    # to debug dns: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#inheriting-dns-from-the-node

    kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

    Write-Information -MessageData "GITHUB_URL: $baseUrl"

    # setting up traefik
    # https://github.com/containous/traefik/blob/master/docs/user-guide/kubernetes.md

    Write-Information -MessageData "Deploying configmaps"
    $folder = "loadbalancer/configmaps"
    if ($ssl) {
        $files = "config.ssl.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }
    else {
        $files = "config.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }

    $kubectlversion = $(kubectl version --short=true)[1]
    if ($kubectlversion -match "v1.8") {
        Write-Information -MessageData "Since kubectlversion ($kubectlversion) is less than 1.9 no roles are needed"
    }
    else {
        Write-Information -MessageData "Deploying roles"
        $folder = "loadbalancer/roles"
        $files = "ingress-roles.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }

    Write-Information -MessageData "Deploying pods"
    $folder = "loadbalancer/pods"

    if ($ingressExternal -eq "onprem" ) {
        $files = "ingress-onprem.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }
    elseif ($ingressInternal -eq "public" ) {
        $files = "ingress-azure.both.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }
    else {
        if ($ssl) {
            $files = "ingress-azure.ssl.yaml ingress-azure.internal.ssl.yaml"
            DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
        }
        else {
            $files = "ingress-azure.yaml ingress-azure.internal.yaml"
            DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
        }    
    }

    Write-Information -MessageData "Deploying services"
    $folder = "loadbalancer/services/cluster"
    $files = "dashboard.yaml dashboard-internal.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid

    Write-Information -MessageData "Deploying ingress"
    $folder = "loadbalancer/ingress"

    if ($ssl ) {
        $files = "dashboard.ssl.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }
    else {
        $files = "dashboard.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid
    }

    $folder = "loadbalancer/services/external"

    if ($ingressExternal -eq "onprem" ) {
        Write-Information -MessageData "Setting up external load balancer"
        $files = "loadbalancer.onprem.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid -public_ip $publicip
    }    
    elseif ("$ingressExternal" -ne "vnetonly") {
        Write-Information -MessageData "Setting up a public load balancer"

        Write-Information -MessageData "Using Public IP: [$publicip]"

        Write-Information -MessageData "Setting up external load balancer"
        $files = "loadbalancer.external.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid -public_ip $publicip
    }
    else {
        Write-Information -MessageData "Setting up an external load balancer"
        $files = "loadbalancer.external.restricted.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid -public_ip $publicip
    }


    if ($ingressExternal -eq "onprem" ) {
    }
    elseif ("$ingressInternal" -eq "public") {
        Write-Information -MessageData "Setting up an internal load balancer"
        $files = "loadbalancer.internal.open.yaml"
    }
    else {
        Write-Information -MessageData "Setting up an internal load balancer"
        $files = "loadbalancer.internal.yaml"
    }
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $baseUrl -customerid $customerid -public_ip $publicip

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

function global:FixLabelOnMaster(){
    # for some reaosn ACS doesn't set this label on the master correctly and we need it to target pods to the master
    Write-Information -MessageData "Looking for node with label [kubernetes.io/role=master]"
    $masternodename=$(kubectl get nodes -l kubernetes.io/role=master -o jsonpath="{.items[0].metadata.name}")
    if(![string]::IsNullOrEmpty($masternodename)){
        Write-Information -MessageData "Setting label [node-role.kubernetes.io/master] on node [$masternodename]"
        kubectl label nodes $masternodename node-role.kubernetes.io/master=""
    }
    else {
        Write-Information -MessageData "No node found with label [kubernetes.io/role=master]"        
    }
}

function global:TestFunction(){
    param( [string]$namespace, [string]$size)     

    [hashtable]$Return = @{} 

    Write-Information -MessageData "namespace: $namespace"
    Write-Information -MessageData "size: $size"

    $Return.Namespace = "$namespace $size"
    return $Return    
}
# --------------------
Write-Information -MessageData "end common-kube.ps1 version $versioncommon"