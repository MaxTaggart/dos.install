
versioncommon="2018.04.11.01"

echo "--- Including common.sh version $versioncommon ---"
function GetCommonVersion() {
    echo $versioncommon
}

function Write-Output()
{
    echo $1
}

function Write-Host()
{
    echo $1
}

# function ReplaceText(){
#     local currentText=$1
#     local replacementText=$2

# # have to do this to preserve the tabs in the file per https://askubuntu.com/questions/267384/using-read-without-losing-the-tab
#     old_IFS=$IFS      # save the field separator           
#     IFS=$'\n'     # new field separator, the end of line

#     while read -r line || [[ -n $line ]]; do echo "${line//$1/$2}"; done

#     IFS=$old_IFS     # restore default field separator
# }

function ReadSecretValue() {
    local secretname=$1
    local valueName=$2
    local namespace=$3
    if [[ -z "$namespace" ]]; then 
        namespace="default"
    fi

    secretbase64=$(kubectl get secret $secretname -o jsonpath="{.data.${valueName}}" -n $namespace --ignore-not-found=true)

    if [[ ! -z "$secretbase64" ]]; then 
        secretvalue=$(echo $secretbase64 | base64 --decode)
        echo $secretvalue
    else
        echo "";
    fi
}

function ReadSecret() {
    local secretname=$1
    local namespace=$2
    ReadSecretValue $secretname "value" $namespace
}

function ReadSecretPassword() {
    local secretname=$1
    local namespace=$2

    ReadSecretValue $secretname "password" $namespace
}

function SaveSecretValue() {
    local secretname=$1
    local valueName=$2
    local myvalue=$3
    local namespace=$4

    # secretname must be lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character
    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ ! -z  "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
        kubectl delete secret $secretname -n $namespace
    fi

    kubectl create secret generic $secretname --namespace=$namespace --from-literal=${valueName}=$myvalue
}

function GeneratePassword() {
    local Length=3
    local set1="abcdefghijklmnopqrstuvwxyz"
    local set2="0123456789"
    local set3="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local set4='!.*@'
    local result=""

    # bash loops: https://www.cyberciti.biz/faq/bash-for-loop/
    for (( c=1; c<$Length; c++ ))
    do  
        result="${result}${set1:RANDOM%${#set1}:1}"
        result="${result}${set2:RANDOM%${#set2}:1}"
        result="${result}${set3:RANDOM%${#set3}:1}"
        result="${result}${set4:RANDOM%${#set4}:1}"
    done
    echo $result
}

function AskForPassword () {
    local secretname=$1
    local prompt=$2
    local namespace=$3

    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
        mysqlrootpassword=""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        read -p "$prompt (leave empty for auto-generated)" mypasswordsecure < /dev/tty
        echo "" # to get a new line
        if [[ -z  "$mypasswordsecure" ]]; then
            mypassword="$(GeneratePassword)"
        else
            mypassword=$mypasswordsecure
        fi

        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mypassword
    else 
        Write-Output "$secretname secret already set so will reuse it"
    fi
}

function AskForPasswordAnyCharacters () {
    local secretname=$1
    local prompt=$2
    local namespace=$3
    local defaultvalue=$4

    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
        mysqlrootpassword=""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        read -p "$prompt (leave empty for auto-generated)" mypasswordsecure < /dev/tty
        echo "" # to get a new line
        if [[ -z  "$mypasswordsecure" ]]; then
            mypassword="$defaultvalue"
        else
            mypassword=$mypasswordsecure
        fi
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mypassword
    else 
        Write-Output "$secretname secret already set so will reuse it"
    fi
}

function AskForSecretValue () {
    local secretname=$1
    local prompt=$2
    local namespace=$3

    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        read -p "${prompt}: " myvalue < /dev/tty
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$myvalue
    else 
        Write-Output "$secretname secret already set so will reuse it"
    fi
}


function WaitForPodsInNamespace(){
    local namespace="$1"
    local interval=$2

    pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    waitingonPod="n"
    while [[ ! -z $waitingonPod ]]; do
        waitingonPod=""
        echo "---- waiting until all pods are running ---"

        for pod in $pods; do
            podstatus=$(kubectl get pods $pod -n $namespace -o jsonpath='{.status.phase}')
            if [[ $podstatus != "Running" ]]; then
                echo "$pod: $podstatus"
                waitingonPod=$pod
            else
                containerReady=$(kubectl get pods $pod -n $namespace -o jsonpath="{.status.containerStatuses[0].ready}")
                if [[ $containerReady != "true" ]]; then
                    waitingonPod=$pod
                    echo "container in $pod is not ready yet: $containerReady"
                fi
            fi
        done
        sleep $interval
    done     
}

function mountSharedFolder(){
    local saveIntoSecret=$1

    echo "DOS requires a network folder that can be accessed from all the worker VMs"
    echo "1. Mount an existing Azure file share"
    echo "2. Mount an existing UNC network file share"
    echo "3. I've already mounted a shared folder at /mnt/data/"

    while [[ -z "$mountChoice" ]]; do
        read -p "Choose a number: " mountChoice < /dev/tty    
    done      
    if [[ $mountChoice == 1 ]]; then
        mountAzureFile $saveIntoSecret
    elif [[ $mountChoice == 2 ]]; then
        mountSMB $saveIntoSecret
    else
        echo "User will mount a shared folder manually"
    fi
}

function mountSMB(){
    local saveIntoSecret=$1

    while [[ -z "$pathToShare" ]]; do
        read -p "path to SMB share (e.g., //myserver.mydomain/myshare): " pathToShare < /dev/tty    
    done  
    while [[ -z "$username" ]]; do
    read -p "username: " username < /dev/tty
    done  
    while [[ -z "$password" ]]; do
        read -p "password: " password < /dev/tty
    done  

    mountSMBWithParams $pathToShare $username $password $saveIntoSecret
}

function mountAzureFile(){
    local saveIntoSecret=$1
    
    while [[ -z "$storageAccountName" ]]; do
        read -p "Storage Account Name: " storageAccountName < /dev/tty  
    done  
    while [[ -z "$shareName" ]]; do
        read -p "Storage Share Name: " shareName < /dev/tty    
    done  
    pathToShare="//${storageAccountName}.file.core.windows.net/${shareName}"
    username="$storageAccountName"
    while [[ -z "$storageAccountKey" ]]; do
        read -p "storage account key: " storageAccountKey < /dev/tty
    done

    mountSMBWithParams $pathToShare $username $storageAccountKey $saveIntoSecret
}


function mountSMBWithParams(){
    local pathToShare=$1
    local username=$2 #<storage-account-name>
    local password=$3
    local saveIntoSecret=$4
    # save as secret
    # secretname="sharedfolder"
    # namespace="default"
    # if [[ ! -z  "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
    #     kubectl delete secret $secretname -n $namespace
    # fi

    # kubectl create secret generic $secretname --namespace=$namespace --from-literal=path=$pathToShare --from-literal=username=$username --from-literal=password=$password

    # from: https://docs.microsoft.com/en-us/azure/storage/files/storage-how-to-use-files-linux
    sudo yum -y install samba-client samba-common cifs-utils 

    sudo mkdir -p /mnt/data

    # sudo mount -t cifs $pathToShare /mnt/data -o vers=2.1,username=<storage-account-name>,password=<storage-account-key>,dir_mode=0777,file_mode=0777,serverino

    # remove previous entry for this drive
    grep -v "/mnt/data" /etc/fstab | sudo tee /etc/fstab > /dev/null

    echo "mounting path: $pathToShare using username: $username"

    echo "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab > /dev/null

    sudo mount -a --verbose

    if [[ $saveIntoSecret == true ]]; then
        echo "saving mount information into a secret"
        secretname="mountsharedfolder"
        namespace="default"
        if [[ ! -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
            kubectl delete secret $secretname --namespace=$namespace
        fi
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=path=$pathToShare --from-literal=username=$username --from-literal=password=$password
    fi

    touch "/mnt/data/$(hostname).txt"

    echo "Listing files in shared folder"
    ls -al /mnt/data

}

function CleanOutNamespace(){
    local namespace=$1

    echo "--- Cleaning out any old resources in $namespace ---"

    # note kubectl doesn't like spaces in between commas below
    kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,jobs,cronjobs' --namespace=$namespace --ignore-not-found=true

    # can't delete persistent volume claims since they are not scoped to namespace
    kubectl delete 'pv' -l namespace=$namespace --ignore-not-found=true

    REMAINING_ITEMS="n"
    while [[ ! -z "$REMAINING_ITEMS" ]]; do
        REMAINING_ITEMS=$(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims' --namespace=$namespace -o jsonpath="{.items[*].metadata.name}")
        echo "Waiting on: $REMAINING_ITEMS"
        if [[ ! -z "$REMAINING_ITEMS" ]]; then
            sleep 5
        fi
    done
}

function InstallStack(){
    local baseUrl=$1
    local namespace=$2
    local appfolder=$3
    
    echo "downloading: $baseUrl/kubernetes/installstack.ps1?p=$RANDOM"
    curl -sSL -o installstack.ps1 "$baseUrl/kubernetes/installstack.ps1?p=$RANDOM"
    # clear
    # can't put tee on the next line or pwsh has issues including common files
    pwsh -f installstack.ps1 -namespace "$namespace" -appfolder "$appfolder" -isAzure 0 -NonInteractive    
}

function InstallLoadBalancerStack(){
    local baseUrl=$1
    local customerid=$2
    local ssl=0
    local ingressInternal="public"
    local ingressExternal="onprem"
    local publicIp=""
    
    curl -sSL -o installloadbalancerstack.ps1 "$baseUrl/kubernetes/installloadbalancerstack.ps1?p=$RANDOM"
    # clear
    # can't put tee on the next line or pwsh has issues including common files
    pwsh -f installloadbalancerstack.ps1 -ssl $ssl -ingressInternal $ingressInternal -ingressExternal $ingressExternal -customerid $customerid -publicIp $publicIp -NonInteractive    
}

function ShowCommandToJoinCluster(){
    local baseUrl=$1

    secretname="mountsharedfolder"
    namespace="default"

    local pathToShare=$(ReadSecretValue $secretname "path" $namespace)
    local username=$(ReadSecretValue $secretname "username" $namespace)
    local password=$(ReadSecretValue $secretname "password" $namespace)
    
    echo "Run this command on any new node to join this cluster (this command expires in 24 hours):"
    echo "---- COPY BELOW THIS LINE ----"
    echo "curl -sSL $baseUrl/onprem/setupnode.sh?p=$RANDOM | bash 2>&1 | tee setupnode.log"
    
    if [[ ! -z "$pathToShare" ]]; then
        echo "curl -sSL $baseUrl/onprem/mountfolder.sh | bash -s $pathToShare $username $password 2>&1 | tee mountfolder.log"
    fi
    echo "sudo $(sudo kubeadm token create --print-join-command)"
    echo ""
    echo "---- COPY ABOVE THIS LINE ----"
}

function JoinNodeToCluster(){
    echo "--- resetting kubeadm ---"
    if [ -x "$(command -v kubeadm)" ]; then
        sudo kubeadm reset
    fi    

    echo "-----------------------"
    while [[ -z "$joincommand" ]]; do
        read -p "Paste kubeadm join command here: " joincommand < /dev/tty    
    done      
    echo "--- running command to join cluster ---"
    eval $joincommand
    echo "--- finished running command to join cluster ----"
}

function SetupMaster(){
    local baseUrl=$1
    local singlenode=$2
    
    curl -sSL $baseUrl/onprem/setupnode.sh?p=$RANDOM | bash 2>&1 | tee setupnode.log
    curl -sSL $baseUrl/onprem/setupmasternode.sh?p=$RANDOM | bash 2>&1 | tee setupmaster.log
    if [[ $singlenode == true ]]; then
        echo "enabling master node to run containers"
        # enable master to run containers
        kubectl taint nodes --all node-role.kubernetes.io/master-        
    else
        mountSharedFolder true 2>&1 | tee mountsharedfolder.log
    fi
    # cannot use tee here because it calls a ps1 file
    curl -sSL $baseUrl/onprem/setup-loadbalancer.sh?p=$RANDOM | bash
    InstallStack $baseUrl "kube-system" "dashboard"
    # clear
    echo "--- waiting for pods to run ---"
    WaitForPodsInNamespace kube-system 5    

    if [[ $singlenode == true ]]; then
        echo "Finished setting up a single-node cluster"
    else
        ShowCommandToJoinCluster $baseUrl    
    fi

}

function UninstallDockerAndKubernetes(){
    if [ -x "$(command -v kubeadm)" ]; then
        sudo kubeadm reset
    fi    
    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
    if [ -x "$(command -v docker)" ]; then
        sudo docker system prune -f
        # sudo docker volume rm etcd
    fi
    sudo rm -rf /var/etcd/backups/*
    sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
    sudo yum -y remove docker docker-common docker-selinux docker-engine docker-ce docker-ce-selinux
    sudo yum -y remove docker \
                    docker-client \
                    docker-client-latest \
                    docker-common \
                    docker-latest \
                    docker-latest-logrotate \
                    docker-logrotate \
                    docker-selinux \
                    docker-engine-selinux \
                    docker-engine    
}

function TestDNS(){
    local baseUrl=$1
    echo "To resolve DNS issues: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#debugging-dns-resolution"
    echo "----------- Checking if DNS pods are running -----------"
    kubectl get pods --namespace=kube-system -l k8s-app=kube-dns
    echo "----------- Checking if DNS service is running -----------"
    kubectl get svc --namespace=kube-system
    echo "----------- Checking if DNS endpoints are exposed ------------"
    kubectl get ep kube-dns --namespace=kube-system
    echo "----------- Checking logs for DNS service -----------"
    kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c kubedns
    kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c dnsmasq
    kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c sidecar        
    echo "----------- Creating a busybox pod to test DNS -----------"
    while [[ ! -z "$(kubectl get pods busybox -n default -o jsonpath='{.status.phase}' --ignore-not-found=true)" ]]; do
        echo "Waiting for busybox to terminate"
        echo "."
        sleep 5
    done

    kubectl create -f $baseUrl/kubernetes/test/busybox.yaml
    while [[ "$(kubectl get pods busybox -n default -o jsonpath='{.status.phase}')" != "Running" ]]; do
        echo "."
        sleep 5
    done
    echo "---- resolve.conf ----"
    kubectl exec busybox cat /etc/resolv.conf
    echo "--- testing if we can access internal (pod) network ---"
    kubectl exec busybox nslookup kubernetes.default
    echo "--- testing if we can access external network ---"
    kubectl exec busybox curl www.google.com
    kubectl delete -f $baseUrl/kubernetes/test/busybox.yaml    
}
echo "--- Finished including common.sh version $versioncommon ---"
