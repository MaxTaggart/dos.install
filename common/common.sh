
versioncommon="2018.04.16.10"

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

function Write-Status(){
    log_success "$1";
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
    local namespace=${3:-}
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
    local namespace=${2:-}
    ReadSecretValue $secretname "value" $namespace
}

function ReadSecretPassword() {
    local secretname=$1
    local namespace=${2:-}

    ReadSecretValue $secretname "password" $namespace
}

function SaveSecretValue() {
    local secretname=$1
    local valueName=$2
    local myvalue=$3
    local namespace=${4:-}

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
    local namespace=${3:-}

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
    local namespace=${3:-}
    local defaultvalue=${4:-}

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
    local namespace=${3:-}
    local defaultvalue=${4:-}

    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        myvalue=""
        while [[ -z "$myvalue" ]]; do
            read -p "${prompt}: " myvalue < /dev/tty       
            if [[ -z "$myvalue" ]]; then
                if [[ ! -z "$defaultvalue" ]]; then
                    myvalue=$defaultvalue
                fi
            fi
        done

        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$myvalue
    else 
        Write-Output "$secretname secret already set so will reuse it"
    fi
}


function WaitForPodsInNamespace(){
    local namespace=$1
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
    local saveIntoSecret=${1:false}

    echo "DOS requires a network folder that can be accessed from all the worker VMs"
    echo "1. Mount an existing Azure file share"
    echo "2. Mount an existing UNC network file share"
    echo "3. I've already mounted a shared folder at /mnt/data/"
    echo ""

    while [[ -z "${mountChoice:-}" ]]; do
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
    local saveIntoSecret=${1:false}

    while [[ -z "${pathToShare:-}" ]]; do
        read -p "path to SMB share (e.g., //myserver.mydomain/myshare): " pathToShare < /dev/tty    
    done  
    while [[ -z "${domain:-}" ]]; do
        read -p "domain: " domain < /dev/tty
    done  
    while [[ -z "${username:-}" ]]; do
        read -p "username: " username < /dev/tty
    done  
    while [[ -z "${password:-}" ]]; do
        read -p "password: " password < /dev/tty
    done  

    mountSMBWithParams $pathToShare $username $domain $password $saveIntoSecret true
}

function mountAzureFile(){
    local saveIntoSecret=${1:false}
    
    while [[ -z "${storageAccountName:-}" ]]; do
        read -p "Storage Account Name: " storageAccountName < /dev/tty  
    done  
    while [[ -z "${shareName:-}" ]]; do
        read -p "Storage Share Name: " shareName < /dev/tty    
    done  
    pathToShare="//${storageAccountName}.file.core.windows.net/${shareName}"
    username="$storageAccountName"
    while [[ -z "${storageAccountKey:-}" ]]; do
        read -p "storage account key: " storageAccountKey < /dev/tty
    done

    mountSMBWithParams $pathToShare $username "domain" $storageAccountKey $saveIntoSecret false
}


function mountSMBWithParams(){
    local pathToShare=$1
    local username=$2
    local domain=$3
    local password=$4
    local saveIntoSecret=${5:false}
    local isUNC=${6:false}

    passwordlength=${#password}
    echo "mounting file share with path: [$pathToShare], user: [$username], domain: [$domain], password_length: [$passwordlength] saveIntoSecret: [$saveIntoSecret], isUNC: [$isUNC]"
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

    if [[ $isUNC == true ]]; then
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm
        echo "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm" | sudo tee -a /etc/fstab > /dev/null
    else
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino
        echo "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab > /dev/null
    fi

    sudo mount -a --verbose

    if [[ $saveIntoSecret == true ]]; then
        echo "saving mount information into a secret"
        secretname="mountsharedfolder"
        namespace="default"
        if [[ ! -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
            kubectl delete secret $secretname --namespace=$namespace
        fi
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=path=$pathToShare --from-literal=username=$username --from-literal=domain=$domain --from-literal=password=$password 
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
    local domain=$(ReadSecretValue $secretname "domain" $namespace)
    local password=$(ReadSecretValue $secretname "password" $namespace)
    
    echo "Run this command on any new node to join this cluster (this command expires in 24 hours):"
    echo "---- COPY BELOW THIS LINE ----"
    echo "curl -sSL $baseUrl/onprem/setupnode.sh?p=$RANDOM | bash 2>&1 | tee setupnode.log"
    
    if [[ ! -z "$pathToShare" ]]; then
        echo "curl -sSL $baseUrl/onprem/mountfolder.sh?p=$RANDOM | bash -s $pathToShare $username $domain $password 2>&1 | tee mountfolder.log"
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
    while [[ -z "${joincommand:-}" ]]; do
        read -p "Paste kubeadm join command here: " joincommand < /dev/tty    
    done      
    echo "--- running command to join cluster ---"
    eval $joincommand
    echo "--- finished running command to join cluster ----"
}

function SetupMaster(){
    local baseUrl=$1
    local singlenode=${2:false}
    
    SetupNewNode $baseUrl | tee setupnode.log
    SetupNewMasterNode $baseUrl | tee setupmaster.log
    if [[ $singlenode == true ]]; then
        echo "enabling master node to run containers"
        # enable master to run containers
        # kubectl taint nodes --all node-role.kubernetes.io/master-       
        kubectl taint node --all node-role.kubernetes.io/master:NoSchedule- 
    else
        mountSharedFolder true | tee mountsharedfolder.log
    fi
    # cannot use tee here because it calls a ps1 file
    SetupNewLoadBalancer $baseUrl

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
    kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o wide
    echo "----------- Details about DNS pods -----------"
    kubectl describe pods --namespace=kube-system -l k8s-app=kube-dns    
    echo "----------- Details about flannel pods -----------"
    kubectl logs --namespace kube-system -l app=flannel
    echo "----------- Checking if DNS service is running -----------"
    kubectl get svc --namespace=kube-system
    echo "----------- Checking if DNS endpoints are exposed ------------"
    kubectl get ep kube-dns --namespace=kube-system
    echo "----------- Checking logs for DNS service -----------"
    # kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name)
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
    kubectl exec busybox wget www.google.com
    kubectl delete -f $baseUrl/kubernetes/test/busybox.yaml    
    echo "--- firewall logs ---"
    sudo systemctl status firewalld -l
}

function ShowStatusOfAllPodsInNameSpace(){
    local namespace=$1
    echo "showing status of pods in $namespace"
    pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods
    do
            Write-Output "=============== Describe Pod: $pod ================="
            kubectl describe pods $pod -n $namespace
#            read -n1 -r -p "Press space to continue..." key < /dev/tty
    done    
}
function ShowLogsOfAllPodsInNameSpace(){
    local namespace=$1
    echo "showing logs (last 20 lines) in $namespace"
    pods=$(kubectl get pods -n $namespace -o jsonpath='{.items[*].metadata.name}')
    for pod in $pods
    do
        Write-Output "=============== Logs for Pod: $pod ================="
        kubectl logs --tail=20 $pod -n $namespace
#            read -n1 -r -p "Press space to continue..." key < /dev/tty
    done    
}

function ConfigureIpTables(){
  echo "switching from firewalld to iptables"
  # iptables-services: for iptables firewall  
  sudo yum -y install iptables-services
  # https://www.digitalocean.com/community/tutorials/how-to-migrate-from-firewalld-to-iptables-on-centos-7
  sudo systemctl stop firewalld && sudo systemctl start iptables; 
  # sudo systemctl start ip6tables
  # sudo firewall-cmd --state
  sudo systemctl disable firewalld
  sudo systemctl enable iptables
  # sudo systemctl enable ip6tables

  echo "--- removing firewalld ---"
  sudo yum -y remove firewalld
  
  echo "setting up iptables rules"
  # https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands
  echo "fixing kubedns"
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -I INPUT -p tcp -m tcp --dport 8472 -j ACCEPT
  sudo iptables -I INPUT -p tcp -m tcp --dport 6443 -j ACCEPT
  sudo iptables -I INPUT -p tcp -m tcp --dport 9898 -j ACCEPT
  sudo iptables -I INPUT -p tcp -m tcp --dport 10250 -j ACCEPT  
  sudo iptables -I INPUT -p tcp -m tcp --dport 443 -j ACCEPT  
  sudo iptables -I INPUT -p tcp -m tcp --dport 8081 -j ACCEPT  
  # echo "allow all outgoing connections"
  # sudo iptables -I OUTPUT -o eth0 -d 0.0.0.0/0 -j ACCEPT
  echo "allowing loopback connections"
  sudo iptables -A INPUT -i lo -j ACCEPT
  sudo iptables -A OUTPUT -o lo -j ACCEPT
  echo "allowing established and related incoming connections"
  sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  echo "allowing established outgoing connections"
  sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
  echo "allowing docker containers to access the external network"
  sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
  sudo iptables -A FORWARD -i docker0 -o eth0 -j ACCEPT
  echo "allow all incoming ssh"
  sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  sudo iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
  # reject an IP address
  # sudo iptables -A INPUT -s 15.15.15.51 -j REJECT
  echo "allow incoming HTTP"
  sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  sudo iptables -A OUTPUT -p tcp --sport 80 -m conntrack --ctstate ESTABLISHED -j ACCEPT
  echo "allow incoming HTTPS"
  sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  sudo iptables -A OUTPUT -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT
  #echo "block outgoing SMTP Mail"
  #sudo iptables -A OUTPUT -p tcp --dport 25 -j REJECT
  
  echo "--- reloading iptables ---"
  sudo systemctl reload iptables
  # echo "--- saving iptables ---"
  # sudo iptables-save
  # echo "--- restarting iptables ---"
  # sudo systemctl restart iptables
  echo "--- status of iptables --"
  sudo systemctl status iptables
  echo "---- current iptables rules ---"
  sudo iptables -t nat -L
}

function ConfigureFirewall(){
  echo " --- installing firewalld ---"
  # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-firewalld-on-centos-7
  sudo yum -y install firewalld
  sudo systemctl status firewalld
  echo "--- removing iptables ---"
  sudo yum -y remove iptables-services
  echo "enabling ports 6443 & 10250 for kubernetes and 80 & 443 for web apps in firewalld"
  # https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
  # kubernetes ports: https://kubernetes.io/docs/setup/independent/install-kubeadm/#check-required-ports
  # https://github.com/coreos/coreos-kubernetes/blob/master/Documentation/kubernetes-networking.md
  # https://github.com/coreos/tectonic-docs/blob/master/Documentation/install/rhel/installing-workers.md
  echo "opening port 6443 for Kubernetes API server"
  sudo firewall-cmd --add-port=6443/tcp --permanent # kubernetes API server
  echo "opening ports 2379-2380 for Kubernetes API server"
  sudo firewall-cmd --add-port=2379-2380/tcp --permanent 
  echo "opening port 8472,8285 and 4789 for Flannel networking"
  sudo firewall-cmd --add-port=8472/udp --permanent  # flannel networking
  sudo firewall-cmd --add-port=8285/udp --permanent  # flannel networking
  sudo firewall-cmd --add-port 4789/udp --permanent
  echo "opening ports 10250,10251,10252 and 10255 for Kubelet API"
  sudo firewall-cmd --add-port=10250/tcp --permanent  # Kubelet API
  sudo firewall-cmd --add-port=10251/tcp --permanent 
  sudo firewall-cmd --add-port=10252/tcp --permanent 
  sudo firewall-cmd --add-port=10255/tcp --permanent # Read-only Kubelet API
  echo "opening ports 80 and 443 for HTTP and HTTPS"
  sudo firewall-cmd --add-port=80/tcp --permanent # HTTP
  sudo firewall-cmd --add-port=443/tcp --permanent # HTTPS
  echo "Opening port 53 for internal DNS"
  sudo firewall-cmd --add-port=53/udp --permanent # DNS
  sudo firewall-cmd --add-port=53/tcp --permanent # DNS
  sudo firewall-cmd --add-port=67/udp --permanent # DNS
  sudo firewall-cmd --add-port=68/udp --permanent # DNS
  sudo firewall-cmd --add-port=30000-60000/udp --permanent # DNS
  sudo firewall-cmd --add-service=dns --permanent # DNS
  echo "Adding NTP service to firewall"
  sudo firewall-cmd --add-service=ntp --permanent # NTP server
  echo "enable all communication between pods"
  # sudo firewall-cmd --zone=trusted --add-interface eth0
  # sudo firewall-cmd --set-default-zone=trusted
  # sudo firewall-cmd --get-zone-of-interface=docker0
  # sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0  

  # https://basildoncoder.com/blog/logging-connections-with-firewalld.html
  # sudo firewall-cmd --zone=public --add-rich-rule="rule family="ipv4" source address="198.51.100.0/32" port protocol="tcp" port="10000" log prefix="test-firewalld-log" level="info" accept"
  # sudo tail -f /var/log/messages |grep test-firewalld-log

  # echo "log dropped packets"
  # sudo firewall-cmd  --set-log-denied=all
  
  # flannel settings
  # from https://github.com/kubernetes/contrib/blob/master/ansible/roles/flannel/tasks/firewalld.yml
  # echo "Open flanneld subnet traffic"
  # sudo firewall-cmd --direct --add-rule ipv4 filter FORWARD 1 -i flannel.1 -j ACCEPT -m comment --comment "flannel subnet"  

  # echo "Save flanneld subnet traffic"
  # sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -i flannel.1 -j ACCEPT -m comment --comment "flannel subnet"

  # echo "Open flanneld to DNAT'ed traffic"
  # sudo firewall-cmd --direct --add-rule ipv4 filter FORWARD 1 -o flannel.1 -j ACCEPT -m comment --comment "flannel subnet"

  # echo "Save flanneld to DNAT'ed traffic"
  # sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -o flannel.1 -j ACCEPT -m comment --comment "flannel subnet"

  echo "--- enable logging of rejected packets ---"
  sudo firewall-cmd --set-log-denied=all

  # http://wrightrocket.blogspot.com/2017/11/installing-kubernetes-on-centos-7-with.html
  echo "reloading firewall"
  sudo firewall-cmd --reload

  sudo systemctl status firewalld  

  echo "--- services enabled in firewall ---"
  sudo firewall-cmd --list-services
  echo "--- ports enabled in firewall ---"
  sudo firewall-cmd --list-ports

  sudo firewall-cmd --list-all
}

function SetupNewMasterNode(){
    local baseUrl=$1

    kubernetesversion="1.9.6"

    u="$(whoami)"
    echo "User name: $u"

    # for calico network plugin
    # echo "--- running kubeadm init for calico ---"
    # sudo kubeadm init --kubernetes-version=v1.9.6 --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true

    # CLUSTER_DNS_CORE_DNS="true"

    # echo "--- running kubeadm init for flannel ---"
    # for flannel network plugin
    # sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true
    sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16

    echo "Troubleshooting kubeadm: https://kubernetes.io/docs/setup/independent/troubleshooting-kubeadm/"

    # which CNI plugin to use: https://chrislovecnm.com/kubernetes/cni/choosing-a-cni-provider/

    # for logs, sudo journalctl -xeu kubelet

    echo "--- copying kube config to $HOME/.kube/config ---"
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # calico
    # from https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/
    # echo "--- enabling calico network plugin ---"
    # http://leebriggs.co.uk/blog/2017/02/18/kubernetes-networking-calico.html
    # kubectl apply -f ${GITHUB_URL}/kubernetes/cni/calico.yaml

    # flannel
    # kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
    echo "--- enabling flannel network plugin ---"
    kubectl apply -f ${baseUrl}/kubernetes/cni/flannel.yaml

    echo "--- sleeping 10 secs to wait for pods ---"
    sleep 10

    echo "adding cni0 network interface to trusted zone"
    sudo firewall-cmd --zone=trusted --add-interface cni0 --permanent
    # sudo firewall-cmd --zone=trusted --add-interface docker0 --permanent
    sudo firewall-cmd --reload


    echo "--- kubelet status ---"
    sudo systemctl status kubelet

    # enable master to run containers
    # kubectl taint nodes --all node-role.kubernetes.io/master-

    # kubectl create -f "$GITHUB_URL/azure/cafe-kube-dns.yml"
    echo "--- nodes ---"
    kubectl get nodes

    echo "--- sleep for 10 secs ---"
    sleep 10

    echo "--- current pods ---"
    kubectl get pods -n kube-system -o wide

    echo "--- waiting for pods to run ---"
    WaitForPodsInNamespace kube-system 5

    echo "--- current pods ---"
    kubectl get pods -n kube-system -o wide

    if [[ ! -d "/mnt/data" ]]; then
        echo "--- creating /mnt/data ---"
        sudo mkdir -p /mnt/data
        sudo chown $(id -u):$(id -g) /mnt/data
        sudo chmod -R 777 /mnt/data
    fi

    # testing
    # kubectl run nginx --image=nginx --port=80

    # Start PowerShell
    # pwsh

    echo "opening port 6661 for mirth"
    sudo firewall-cmd --add-port=6661/tcp --permanent
    echo "opening port 5671 for rabbitmq"
    sudo firewall-cmd --add-port=5671/tcp --permanent  # flannel networking
    echo "opening port 3307 for mysql"
    sudo firewall-cmd --add-port 3307/tcp --permanent
    echo "reloading firewall"
    sudo firewall-cmd --reload
    
}

function SetupNewLoadBalancer(){
    local baseUrl=$1

    # enable running pods on master
    # kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule
    echo "--- deleting existing resources with label traefik ---"
    kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

    echo "--- deleting existing service account for traefik ---"
    kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

    AKS_IP_WHITELIST=""
    publicip=""

    AskForSecretValue "customerid" "Customer ID "
    echo "reading secret from kubernetes"
    customerid=$(ReadSecret "customerid")

    fullhostname=$(hostname --fqdn)
    echo "Full host name of current machine: $fullhostname"
    AskForSecretValue "dnshostname" "DNS name used to connect to the master VM (leave empty to use $fullhostname)" "default" $fullhostname
    dnsrecordname=$(ReadSecret "dnshostname")

    sslsecret=$(kubectl get secret traefik-cert-ahmn -n kube-system --ignore-not-found=true)

    if [[ -z "$sslsecret" ]]; then

            read -p "Location of SSL cert files (tls.crt and tls.key): (leave empty to use self-signed certificates) " certfolder < /dev/tty

            if [[ -z "$certfolder" ]]; then
                    echo "Creating self-signed SSL certificate"
                    sudo yum -y install openssl
                    u="$(whoami)"
                    certfolder="/opt/healthcatalyst/certs"
                    echo "Creating folder: $certfolder and giving access to $u"
                    sudo mkdir -p "$certfolder"
                    sudo setfacl -m u:$u:rwx "$certfolder"
                    rm -rf "$certfolder/*"
                    cd "$certfolder"
                    # https://gist.github.com/fntlnz/cf14feb5a46b2eda428e000157447309
                    echo "Generating CA cert"
                    openssl genrsa -out rootCA.key 2048
                    openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -subj /CN=HCKubernetes/O=HealthCatalyst/ -out rootCA.crt
                    echo "Generating certificate for $dnsrecordname"
                    openssl genrsa -out tls.key 2048
                    openssl req -new -key tls.key -subj /CN=$dnsrecordname/O=HealthCatalyst/ -out tls.csr
                    openssl x509 -req -in tls.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out tls.crt -days 3650 -sha256
                    cp tls.crt tls.pem
            fi

            ls -al "$certfolder"

            echo "Deleting any old TLS certs"
            kubectl delete secret traefik-cert-ahmn -n kube-system --ignore-not-found=true

            echo "Storing TLS certs as kubernetes secret"
            kubectl create secret generic traefik-cert-ahmn -n kube-system --from-file="$certfolder/tls.crt" --from-file="$certfolder/tls.key"
    fi

    InstallLoadBalancerStack $GITHUB_URL "$customerid"    
}
function SetupNewNode(){
    local baseUrl=$1

    export dockerversion="17.03.2.ce-1"
    export kubernetesversion="1.9.6-0"
    # 1.9.3-0
    # 1.9.6-0
    # 1.10.0-0
    export kubernetescniversion="0.6.0-0"

    echo "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    u="$(whoami)"
    echo "User name: $u"

    Write-Status "--- updating yum packages ---"
    sudo yum update -y

    echo "---- RAM ----"
    free -h
    echo "--- disk space ---"
    df -h

    Write-Status "installing yum-utils and other packages"
    # yum-version: lock yum packages so they don't update automatically
    # yum-utils: for yum-config-manager
    # net-tools: for DNS tools
    # nmap: nmap command for listing open ports
    # curl: for downloading
    # lsof: show open files
    # ntp: Network Time Protocol
    # nano: simple editor
    # bind-utils: for dig, host

    sudo yum -y install yum-versionlock yum-utils net-tools nmap curl lsof ntp nano bind-utils

    Write-Status "removing unneeded packages"
    # https://www.tecmint.com/remove-unwanted-services-in-centos-7/
    sudo yum -y remove postfix chrony

    Write-Status "turning off swap"
    # https://blog.alexellis.io/kubernetes-in-10-minutes/
    sudo swapoff -a
    echo "removing swap from /etc/fstab"
    grep -v "swap" /etc/fstab | sudo tee /etc/fstab
    echo "--- current swap files ---"
    sudo cat /proc/swaps

    ConfigureFirewall
    # ConfigureIpTables

    # Register the Microsoft RedHat repository
    echo "--- adding microsoft repo for powershell ---"
    sudo yum-config-manager \
    --add-repo \
    https://packages.microsoft.com/config/rhel/7/prod.repo

    # curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo

    # Install PowerShell
    echo "--- installing powershell ---"
    sudo yum install -y powershell
    # sudo yum install -y powershell-6.0.2-1.rhel.7
    # sudo yum versionlock powershell

    Write-Status "-- starting NTP deamon ---"
    # https://www.tecmint.com/install-ntp-server-in-centos/
    sudo systemctl start ntpd
    sudo systemctl enable ntpd
    sudo systemctl status ntpd

    Write-Status "--- stopping docker and kubectl ---"
    servicestatus=$(systemctl show -p SubState kubelet)
    if [[ $servicestatus = *"running"* ]]; then
    echo "stopping kubelet"
    sudo systemctl stop kubelet
    fi

    # remove older versions
    # sudo systemctl stop docker 2>/dev/null
    Write-Status "--- Removing previous versions of kubernetes and docker --"
    if [ -x "$(command -v kubeadm)" ]; then
    sudo kubeadm reset
    fi

    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
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
                    
    # sudo rm -rf /var/lib/docker

    Write-Status "--- Adding docker repo --"
    sudo yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo

    Write-Status " --- current repo list ---"
    sudo yum -y repolist

    Write-Status "-- docker versions available in repo --"
    sudo yum -y --showduplicates list docker-ce

    Write-Status "--- Installing docker via yum --"
    echo "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    # need to pass --setpot=obsoletes=0 due to this bug: https://github.com/docker/for-linux/issues/20#issuecomment-312122325
    sudo yum install -y --setopt=obsoletes=0 docker-ce-${dockerversion}.el7.centos docker-ce-selinux-${dockerversion}.el7.centos
    Write-Status "--- Locking version of docker so it does not get updated via yum update --"
    sudo yum versionlock docker-ce
    sudo yum versionlock docker-ce-selinux

    # https://kubernetes.io/docs/setup/independent/install-kubeadm/
    # log rotation for docker: https://docs.docker.com/config/daemon/
    # https://docs.docker.com/config/containers/logging/json-file/
    Write-Status "--- Configuring docker to use systemd and set logs to max size of 10MB and 5 days --"
    sudo mkdir -p /etc/docker
    sudo curl -sSL -o /etc/docker/daemon.json ${baseUrl}/onprem/daemon.json?p=$RANDOM
    
    Write-Status "--- Starting docker service --"
    sudo systemctl enable docker && sudo systemctl start docker

    if [ $u != "root" ]; then
        Write-Status "--- Giving permission to $u to interact with docker ---"
        sudo usermod -aG docker $u
        # reload permissions without requiring a logout
        # from https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
        # https://man.cx/newgrp(1)
        Write-Status "--- Reloading permissions via newgrp ---"
        newgrp docker
    fi

    echo "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    echo "--- docker status ---"
    sudo systemctl status docker

    Write-Status "--- Adding kubernetes repo ---"
    sudo yum-config-manager \
        --add-repo \
        ${baseUrl}/onprem/kubernetes.repo

    # install kubeadm
    # https://saurabh-deochake.github.io/posts/2017/07/post-1/
    Write-Status "setting selinux to disabled so kubernetes can work"
    sudo setenforce 0
    sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    # sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux

    Write-Status "--- Removing previous versions of kubernetes ---"
    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni

    Write-Status "--- checking to see if port 10250 is still busy ---"
    sudo lsof -i -P -n | grep LISTEN

    Write-Status "--- kubernetes versions available in repo ---"
    sudo yum -y --showduplicates list kubelet kubeadm kubectl kubernetes-cni

    Write-Status "--- installing kubernetes ---"
    echo "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    sudo yum install -y "kubelet-${kubernetesversion}" "kubeadm-${kubernetesversion}" "kubectl-${kubernetesversion}" "kubernetes-cni-${kubernetescniversion}"
    Write-Status "--- locking versions of kubernetes so they don't get updated by yum update ---"
    sudo yum versionlock kubelet
    sudo yum versionlock kubeadm
    sudo yum versionlock kubectl
    sudo yum versionlock kubernetes-cni

    Write-Status "--- starting kubernetes service ---"
    sudo systemctl enable kubelet && sudo systemctl start kubelet

    # echo "--- setting up iptables for kubernetes ---"
    # # Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
    # cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
    # net.bridge.bridge-nf-call-ip6tables = 1
    # net.bridge.bridge-nf-call-iptables = 1
    # EOF
    # sudo sysctl --system

    Write-Status "--- finished setting up node ---"

}

function createShortcutFordos(){
    local baseUrl=$1

    mkdir -p $HOME/bin
    installscript="$HOME/bin/dos"
    if [[ ! -f "$installscript" ]]; then
        echo "#!/bin/bash" > $installscript
        echo "curl -sSL $baseUrl/"'onprem/main.sh?p=$RANDOM | bash' >> $installscript
        chmod +x $installscript
        echo "NOTE: Next time just type 'dos' to bring up this menu"

        # from http://web.archive.org/web/20120621035133/http://www.ibb.net/~anne/keyboard/keyboard.html
        # curl -o ~/.inputrc "$GITHUB_URL/kubernetes/inputrc"
    fi    
}

echo "--- Finished including common.sh version $versioncommon ---"
