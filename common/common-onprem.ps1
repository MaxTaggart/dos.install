$versiononpremcommon = "2018.04.17.06"

Write-Information -MessageData "Including common-onprem.ps1 version $versiononpremcommon"
function global:GetCommonOnPremVersion() {
    return $versiononpremcommon
}

function WriteOut($txt) {
    Write-Information -MessageData "$txt"
}

function Write-Status($txt) {
    Write-Information -MessageData "$txt"
}

function SetupMaster([ValidateNotNullOrEmpty()][string] $baseUrl, [bool]$singlenode) {
    [hashtable]$Return = @{} 
    
    SetupNewNode -baseUrl $baseUrl
    SetupNewMasterNode -baseUrl $baseUrl

    if ($singlenode -eq $True) {
        WriteOut "enabling master node to run containers"
        # enable master to run containers
        # kubectl taint nodes --all node-role.kubernetes.io/master-       
        kubectl taint node --all node-role.kubernetes.io/master:NoSchedule- 
    }
    else {
        mountSharedFolder -saveIntoSecret $True
    }
    # cannot use tee here because it calls a ps1 file
    SetupNewLoadBalancer -baseUrl $baseUrl

    InstallStack -baseUrl $baseUrl -namespace "kube-system" -appfolder "dashboard"
    # clear
    WriteOut "--- waiting for pods to run ---"
    WaitForPodsInNamespace -namespace "kube-system" -interval 5    

    if ($singlenode -eq $True) {
        WriteOut "Finished setting up a single-node cluster"
    }
    else {
        ShowCommandToJoinCluster $baseUrl    
    }

    return $Return    
}

function SetupNewMasterNode([ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    $kubernetesversion = "1.9.6"

    $u = "$(whoami)"
    WriteOut "User name: $u"

    # for calico network plugin
    # WriteOut "--- running kubeadm init for calico ---"
    # sudo kubeadm init --kubernetes-version=v1.9.6 --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true

    # CLUSTER_DNS_CORE_DNS="true"

    # WriteOut "--- running kubeadm init for flannel ---"
    # for flannel network plugin
    # sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true
    sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16

    WriteOut "Troubleshooting kubeadm: https://kubernetes.io/docs/setup/independent/troubleshooting-kubeadm/"

    # which CNI plugin to use: https://chrislovecnm.com/kubernetes/cni/choosing-a-cni-provider/

    # for logs, sudo journalctl -xeu kubelet

    WriteOut "--- copying kube config to $HOME/.kube/config ---"
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    WriteOut "sudo chown $(id -u):$(id -g) $HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" $HOME/.kube/config

    # calico
    # from https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/
    # WriteOut "--- enabling calico network plugin ---"
    # http://leebriggs.co.uk/blog/2017/02/18/kubernetes-networking-calico.html
    # kubectl apply -f ${GITHUB_URL}/kubernetes/cni/calico.yaml

    # flannel
    # kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
    WriteOut "--- enabling flannel network plugin ---"
    kubectl apply -f ${baseUrl}/kubernetes/cni/flannel.yaml

    WriteOut "--- sleeping 10 secs to wait for pods ---"
    Start-Sleep 10

    WriteOut "adding cni0 network interface to trusted zone"
    sudo firewall-cmd --zone=trusted --add-interface cni0 --permanent
    # sudo firewall-cmd --zone=trusted --add-interface docker0 --permanent
    sudo firewall-cmd --reload

    WriteOut "--- kubelet status ---"
    sudo systemctl status kubelet -l

    # enable master to run containers
    # kubectl taint nodes --all node-role.kubernetes.io/master-

    # kubectl create -f "$GITHUB_URL/azure/cafe-kube-dns.yml"
    WriteOut "--- nodes ---"
    kubectl get nodes

    WriteOut "--- sleep for 10 secs ---"
    Start-Sleep 10

    WriteOut "--- current pods ---"
    kubectl get pods -n kube-system -o wide

    WriteOut "--- waiting for pods to run ---"
    WaitForPodsInNamespace kube-system 5

    WriteOut "--- current pods ---"
    kubectl get pods -n kube-system -o wide

    if (!(Test-Path C:\Windows -PathType Leaf)) {
        WriteOut "--- creating /mnt/data ---"
        sudo mkdir -p "/mnt/data"
        WriteOut "sudo chown $(id -u):$(id -g) /mnt/data"
        sudo chown "$(id -u):$(id -g)" "/mnt/data"
        sudo chmod -R 777 "/mnt/data"
    }

    WriteOut "opening port 6661 for mirth"
    sudo firewall-cmd --add-port=6661/tcp --permanent
    WriteOut "opening port 5671 for rabbitmq"
    sudo firewall-cmd --add-port=5671/tcp --permanent  # flannel networking
    WriteOut "opening port 3307 for mysql"
    sudo firewall-cmd --add-port 3307/tcp --permanent
    WriteOut "reloading firewall"
    sudo firewall-cmd --reload
    
    return $Return    
}

function ConfigureFirewall() {
    [hashtable]$Return = @{} 

    WriteOut " --- installing firewalld ---"
    # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-firewalld-on-centos-7
    sudo yum -y install firewalld
    WriteOut "--- starting firewalld ---"
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    sudo systemctl status firewalld -l
    WriteOut "--- removing iptables ---"
    sudo yum -y remove iptables-services

    WriteOut "Making sure the main network interface is in public zone"
    $primarynic = $(route | grep default | awk '{print $NF; ext }')
    WriteOut "Found primary network interface: $primarynic"
    if ($primarynic) {
        $zoneforprimarynic = $(sudo firewall-cmd --get-zone-of-interface="$primarynic")
        if (!$zoneforprimarynic) {
            WriteOut "Primary network interface, $primarynic, was not in any zone so adding it to public zone"
            sudo firewall-cmd --zone=public --add-interface "$primarynic"
            sudo firewall-cmd --permanent --zone=public --add-interface="$primarynic"
            sudo firewall-cmd --reload
        }
    }

    WriteOut "enabling ports in firewalld"
    # https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
    # kubernetes ports: https://kubernetes.io/docs/setup/independent/install-kubeadm/#check-required-ports
    # https://github.com/coreos/coreos-kubernetes/blob/master/Documentation/kubernetes-networking.md
    # https://github.com/coreos/tectonic-docs/blob/master/Documentation/install/rhel/installing-workers.md
    WriteOut "opening port 22 for SSH"
    sudo firewall-cmd --add-port=22/tcp --permanent # SSH
    WriteOut "opening port 6443 for Kubernetes API server"
    sudo firewall-cmd --add-port=6443/tcp --permanent # kubernetes API server
    WriteOut "opening ports 2379-2380 for Kubernetes API server"
    sudo firewall-cmd --add-port=2379-2380/tcp --permanent 
    WriteOut "opening port 8472,8285 and 4789 for Flannel networking"
    sudo firewall-cmd --add-port=8472/udp --permanent  # flannel networking
    sudo firewall-cmd --add-port=8285/udp --permanent  # flannel networking
    sudo firewall-cmd --add-port 4789/udp --permanent
    WriteOut "opening ports 10250,10251,10252 and 10255 for Kubelet API"
    sudo firewall-cmd --add-port=10250/tcp --permanent  # Kubelet API
    sudo firewall-cmd --add-port=10251/tcp --permanent 
    sudo firewall-cmd --add-port=10252/tcp --permanent 
    sudo firewall-cmd --add-port=10255/tcp --permanent # Read-only Kubelet API
    WriteOut "opening ports 80 and 443 for HTTP and HTTPS"
    sudo firewall-cmd --add-port=80/tcp --permanent # HTTP
    sudo firewall-cmd --add-port=443/tcp --permanent # HTTPS
    WriteOut "Opening port 53 for internal DNS"
    sudo firewall-cmd --add-port=53/udp --permanent # DNS
    sudo firewall-cmd --add-port=53/tcp --permanent # DNS
    sudo firewall-cmd --add-port=67/udp --permanent # DNS
    sudo firewall-cmd --add-port=68/udp --permanent # DNS
    # sudo firewall-cmd --add-port=30000-60000/udp --permanent # NodePort services
    sudo firewall-cmd --add-service=dns --permanent # DNS
    WriteOut "Adding NTP service to firewall"
    sudo firewall-cmd --add-service=ntp --permanent # NTP server
    WriteOut "enable all communication between pods"
    # sudo firewall-cmd --zone=trusted --add-interface eth0
    # sudo firewall-cmd --set-default-zone=trusted
    # sudo firewall-cmd --get-zone-of-interface=docker0
    # sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0  
  
    # https://basildoncoder.com/blog/logging-connections-with-firewalld.html
    # sudo firewall-cmd --zone=public --add-rich-rule="rule family="ipv4" source address="198.51.100.0/32" port protocol="tcp" port="10000" log prefix="test-firewalld-log" level="info" accept"
    # sudo tail -f /var/log/messages |grep test-firewalld-log
  
    # WriteOut "log dropped packets"
    # sudo firewall-cmd  --set-log-denied=all
    
    # flannel settings
    # from https://github.com/kubernetes/contrib/blob/master/ansible/roles/flannel/tasks/firewalld.yml
    # WriteOut "Open flanneld subnet traffic"
    # sudo firewall-cmd --direct --add-rule ipv4 filter FORWARD 1 -i flannel.1 -j ACCEPT -m comment --comment "flannel subnet"  
  
    # WriteOut "Save flanneld subnet traffic"
    # sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -i flannel.1 -j ACCEPT -m comment --comment "flannel subnet"
  
    # WriteOut "Open flanneld to DNAT'ed traffic"
    # sudo firewall-cmd --direct --add-rule ipv4 filter FORWARD 1 -o flannel.1 -j ACCEPT -m comment --comment "flannel subnet"
  
    # WriteOut "Save flanneld to DNAT'ed traffic"
    # sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -o flannel.1 -j ACCEPT -m comment --comment "flannel subnet"
  
    WriteOut "--- enable logging of rejected packets ---"
    sudo firewall-cmd --set-log-denied=all
  
    # http://wrightrocket.blogspot.com/2017/11/installing-kubernetes-on-centos-7-with.html
    WriteOut "reloading firewall"
    sudo firewall-cmd --reload
  
    sudo systemctl status firewalld -l
  
    WriteOut "--- services enabled in firewall ---"
    sudo firewall-cmd --list-services
    WriteOut "--- ports enabled in firewall ---"
    sudo firewall-cmd --list-ports
  
    sudo firewall-cmd --list-all

    return $Return        
}
function SetupNewLoadBalancer([ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    # enable running pods on master
    # kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule
    WriteOut "--- deleting existing resources with label traefik ---"
    kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

    WriteOut "--- deleting existing service account for traefik ---"
    kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

    $publicip = ""

    AskForSecretValue -secretname "customerid" -prompt "Customer ID "
    WriteOut "reading secret from kubernetes"
    $customerid = $(ReadSecret -secretname "customerid")

    $fullhostname = $(hostname --fqdn)
    WriteOut "Full host name of current machine: $fullhostname"
    AskForSecretValue -secretname "dnshostname" -prompt "DNS name used to connect to the master VM (leave empty to use $fullhostname)" -namespace "default" -defaultvalue $fullhostname
    $dnsrecordname = $(ReadSecret -secretname "dnshostname")

    $sslsecret = $(kubectl get secret traefik-cert-ahmn -n kube-system --ignore-not-found=true)

    if (!$sslsecret) {
        $certfolder = Read-Host -Prompt "Location of SSL cert files (tls.crt and tls.key): (leave empty to use self-signed certificates) "

        if (!$certfolder) {
            WriteOut "Creating self-signed SSL certificate"
            sudo yum -y install openssl
            $u = "$(whoami)"
            $certfolder = "/opt/healthcatalyst/certs"
            WriteOut "Creating folder: $certfolder and giving access to $u"
            sudo mkdir -p "$certfolder"
            sudo setfacl -m u:$u:rwx "$certfolder"
            rm -rf "$certfolder/*"
            cd "$certfolder"
            # https://gist.github.com/fntlnz/cf14feb5a46b2eda428e000157447309
            WriteOut "Generating CA cert"
            sudo openssl genrsa -out rootCA.key 2048
            sudo openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -subj /CN=HCKubernetes/O=HealthCatalyst/ -out rootCA.crt
            WriteOut "Generating certificate for $dnsrecordname"
            sudo openssl genrsa -out tls.key 2048
            sudo openssl req -new -key tls.key -subj /CN=$dnsrecordname/O=HealthCatalyst/ -out tls.csr
            sudo openssl x509 -req -in tls.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out tls.crt -days 3650 -sha256
            sudo cp tls.crt tls.pem
            cd "~"
        }

        ls -al "$certfolder"

        WriteOut "Deleting any old TLS certs"
        kubectl delete secret traefik-cert-ahmn -n kube-system --ignore-not-found=true

        WriteOut "Storing TLS certs as kubernetes secret"
        kubectl create secret generic traefik-cert-ahmn -n kube-system --from-file="$certfolder/tls.crt" --from-file="$certfolder/tls.key"
    }

    $ingressInternal = "public"
    $ingressExternal = "onprem"
    $publicIp = ""

    LoadLoadBalancerStack -baseUrl $GITHUB_URL -ssl 0 -ingressInternal $ingressInternal -ingressExternal $ingressExternal -customerid $customerid -publicIp $publicIp    

    return $Return
}

function SetupNewNode([ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    WriteOut "checking if this machine can access a DNS server via host $(hostname)"
    WriteOut "--- /etc/resolv.conf ---"
    sudo cat /etc/resolv.conf
    WriteOut "-----------------------"

    $myip = $(host $(hostname) | awk '/has address/ { print $4 ; exit }')

    if (!$myip) {
        throw "Cannot access my DNS server: host $(hostname)"
        WriteOut "Cannot access my DNS server: host $(hostname)"
        WriteOut "checking if this machine can access a DNS server via host $(hostname)"
        $myip = $(hostname -I | cut -d" " -f 1)
        if ($myip) {
            WriteOut "Found an IP via hostname -I: $myip"
        }
    }
    else {
        WriteOut "My external IP is $myip"
    }

    $dockerversion = "17.03.2.ce-1"
    $kubernetesversion = "1.9.6-0"
    $kubernetescniversion = "0.6.0-0"

    # $(export dockerversion="17.03.2.ce-1")
    # $(export kubernetesversion="1.9.6-0")
    # 1.9.3-0
    # 1.9.6-0
    # 1.10.0-0
    # $(export kubernetescniversion="0.6.0-0")

    WriteOut "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    $u = "$(whoami)"
    WriteOut "User name: $u"


    ConfigureFirewall
    # ConfigureIpTables

    Write-Status "-- starting NTP deamon ---"
    # https://www.tecmint.com/install-ntp-server-in-centos/
    sudo systemctl start ntpd
    sudo systemctl enable ntpd
    sudo systemctl status ntpd -l

    # Write-Status "--- stopping docker and kubectl ---"
    # $servicestatus = $(systemctl show -p SubState kubelet)
    # if [[ $servicestatus = *"running"* ]]; then
    # WriteOut "stopping kubelet"
    # sudo systemctl stop kubelet
    # fi

    # remove older versions
    # sudo systemctl stop docker 2>/dev/null
    Write-Status "--- Removing previous versions of kubernetes and docker --"
    if (![string]::IsNullOrEmpty($(command -v kubeadm))) {
        sudo kubeadm reset
    }

    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
    sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
    sudo yum -y remove docker docker-common docker-selinux docker-engine docker-ce docker-ce-selinux
    sudo yum -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine
                    
    # sudo rm -rf /var/lib/docker

    Write-Status "--- Adding docker repo --"
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    Write-Status " --- current repo list ---"
    sudo yum -y repolist

    Write-Status "-- docker versions available in repo --"
    sudo yum -y --showduplicates list docker-ce

    # https://saurabh-deochake.github.io/posts/2017/07/post-1/
    Write-Status "setting selinux to disabled so kubernetes can work"
    sudo setenforce 0
    sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    # sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux   

    Write-Status "--- Installing docker via yum --"
    WriteOut "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
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
    sudo systemctl enable docker
    sudo systemctl start docker

    if ($u -ne "root") {
        Write-Status "--- Giving permission to $u to interact with docker ---"
        sudo usermod -aG docker $u
        # reload permissions without requiring a logout
        # from https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
        # https://man.cx/newgrp(1)
        Write-Status "--- Reloading permissions via newgrp ---"
        # newgrp docker
    }

    WriteOut "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    WriteOut "--- docker status ---"
    sudo systemctl status docker -l

    Write-Status "--- Adding kubernetes repo ---"
    sudo yum-config-manager --add-repo ${baseUrl}/onprem/kubernetes.repo

    # install kubeadm
    Write-Status "--- Removing previous versions of kubernetes ---"
    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni

    Write-Status "--- checking to see if port 10250 is still busy ---"
    sudo lsof -i -P -n | grep LISTEN

    Write-Status "--- kubernetes versions available in repo ---"
    sudo yum -y --showduplicates list kubelet kubeadm kubectl kubernetes-cni

    Write-Status "--- installing kubernetes ---"
    WriteOut "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    sudo yum install -y "kubelet-${kubernetesversion}" "kubeadm-${kubernetesversion}" "kubectl-${kubernetesversion}" "kubernetes-cni-${kubernetescniversion}"
    Write-Status "--- locking versions of kubernetes so they don't get updated by yum update ---"
    sudo yum versionlock kubelet
    sudo yum versionlock kubeadm
    sudo yum versionlock kubectl
    sudo yum versionlock kubernetes-cni

    Write-Status "--- starting kubernetes service ---"
    sudo systemctl enable kubelet
    sudo systemctl start kubelet

    WriteOut "--- setting up iptables for kubernetes in k8s.conf ---"
    # # Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
    sudo curl -o "/etc/sysctl.d/k8s.conf" -sSL "$baseUrl/onprem/k8s.conf"
    sudo sysctl --system

    Write-Status "--- finished setting up node ---"

    return $Return
}

function UninstallDockerAndKubernetes() {
    [hashtable]$Return = @{} 
    
    if ("$(command -v kubeadm)") {
        sudo kubeadm reset
    }    
    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
    if ("$(command -v docker)") {
        sudo docker system prune -f
        # sudo docker volume rm etcd
    }
    sudo rm -rf /var/etcd/backups/*
    sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
    sudo yum -y remove docker docker-common docker-selinux docker-engine docker-ce docker-ce-selinux
    sudo yum -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine    

    return $Return
}

function mountSharedFolder([ValidateNotNullOrEmpty()][bool] $saveIntoSecret) {
    [hashtable]$Return = @{} 

    Write-Host "DOS requires a network folder that can be accessed from all the worker VMs"
    Write-Host "1. Mount an existing Azure file share"
    Write-Host "2. Mount an existing UNC network file share"
    Write-Host "3. I've already mounted a shared folder at /mnt/data/"
    Write-Host ""

    Do {$mountChoice = Read-Host -Prompt "Choose a number"} while (!$mountChoice)

    if ($mountChoice -eq "1") {
        mountAzureFile -saveIntoSecret $saveIntoSecret
    }
    elseif ($mountChoice -eq "2") {
        mountSMB -saveIntoSecret $saveIntoSecret
    }
    else {
        WriteOut "User will mount a shared folder manually"
    }

    return $Return    
}

function mountSMB([ValidateNotNullOrEmpty()][bool] $saveIntoSecret) {
    [hashtable]$Return = @{} 

    Do {$pathToShare = Read-Host -Prompt "path to SMB share (e.g., //myserver.mydomain/myshare)"} while (!$pathToShare)

    # convert to unix style since that's what linux mount command expects
    $pathToShare = ($pathToShare -replace "\\", "/")
 
    Do {$domain = Read-Host -Prompt "domain"} while (!$domain)

    Do {$username = Read-Host -Prompt "username"} while (!$username)

    Do {$password = Read-Host -Prompt "password"} while (!$password)

    mountSMBWithParams -pathToShare $pathToShare -username $username -domain $domain -password $password -saveIntoSecret$saveIntoSecret -isUNC $True

    return $Return    

}

function mountAzureFile([ValidateNotNullOrEmpty()][bool] $saveIntoSecret) {
    [hashtable]$Return = @{} 
    
    Do {$storageAccountName = Read-Host -Prompt "Storage Account Name"} while (!$storageAccountName)

    Do {$shareName = Read-Host -Prompt "Storage Share Name"} while (!$shareName)

    $pathToShare = "//${storageAccountName}.file.core.windows.net/${shareName}"
    $username = "$storageAccountName"

    Do {$storageAccountKey = Read-Host -Prompt "storage account key"} while (!$storageAccountKey)

    mountSMBWithParams -pathToShare $pathToShare -username $username -domain "domain" -password $storageAccountKey -saveIntoSecret $saveIntoSecret -isUNC $False
    return $Return    
}

function mountSMBWithParams([ValidateNotNullOrEmpty()][string] $pathToShare, [ValidateNotNullOrEmpty()][string] $username, [ValidateNotNullOrEmpty()][string] $domain, [ValidateNotNullOrEmpty()][string] $password, [ValidateNotNullOrEmpty()][bool] $saveIntoSecret, [ValidateNotNullOrEmpty()][bool] $isUNC) {
    [hashtable]$Return = @{} 
    $passwordlength = $($password.length)
    WriteOut "mounting file share with path: [$pathToShare], user: [$username], domain: [$domain], password_length: [$passwordlength] saveIntoSecret: [$saveIntoSecret], isUNC: [$isUNC]"
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

    WriteOut "mounting path: $pathToShare using username: $username"

    if ($isUNC -eq $True) {
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o vers=2.1, username=$username, domain=$domain, password=$password, dir_mode=0777, file_mode=0777, sec=ntlm
        WriteOut "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm" | sudo tee -a /etc/fstab > /dev/null
    }
    else {
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o vers=2.1, username=$username, password=$password, dir_mode=0777, file_mode=0777, serverino
        WriteOut "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab > /dev/null       
    }

    sudo mount -a --verbose

    if ( $saveIntoSecret -eq $True) {
        WriteOut "saving mount information into a secret"
        $secretname = "mountsharedfolder"
        $namespace = "default"
        if ([string]::IsNullOrEmpty("$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)")) {
            kubectl delete secret $secretname --namespace=$namespace
        }
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=path=$pathToShare --from-literal=username=$username --from-literal=domain=$domain --from-literal=password=$password 
    }

    touch "/mnt/data/$(hostname).txt"

    WriteOut "Listing files in shared folder"
    ls -al /mnt/data
    return $Return    
}

function ShowCommandToJoinCluster([ValidateNotNullOrEmpty()][string] $baseUrl) {
    
    WriteOut "Run this command on any new node to join this cluster (this command expires in 24 hours):"
    WriteOut "---- COPY BELOW THIS LINE ----"
    WriteOut "curl -sSL $baseUrl/onprem/setupnode.sh?p="'$RANDOM'" | bash"
    
    # if [[ ! -z "$pathToShare" ]]; then
    #     WriteOut "curl -sSL $baseUrl/onprem/mountfolder.sh?p=$RANDOM | bash -s $pathToShare $username $domain $password 2>&1 | tee mountfolder.log"
    # fi
    WriteOut "sudo $(sudo kubeadm token create --print-join-command)"
    WriteOut ""
    WriteOut "---- COPY ABOVE THIS LINE ----"
}

# --------------------
Write-Information -MessageData "end common-onprem.ps1 version $versiononpremcommon"