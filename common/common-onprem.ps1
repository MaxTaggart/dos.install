$versiononpremcommon = "2018.04.18.05"

Write-Information -MessageData "Including common-onprem.ps1 version $versiononpremcommon"
function global:GetCommonOnPremVersion() {
    return $versiononpremcommon
}

function WriteToLog($txt) {
    Write-Information -MessageData "$txt"
}

function WriteToConsole($txt) {
    Write-Information -MessageData "$txt"
    Write-Host "$txt"
}

function SetupWorker([ValidateNotNullOrEmpty()][string] $baseUrl, [ValidateNotNullOrEmpty()][string] $joincommand) {
    [hashtable]$Return = @{} 
    
    # Set-PSDebug -Trace 1   
    $logfile="$(get-date -f yyyy-MM-dd-HH-mm)-setupworker.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    WriteToConsole "--- cleaning up old stuff ---"
    UninstallDockerAndKubernetes

    WriteToConsole "--- setting up new node ---"
    SetupNewNode -baseUrl $baseUrl

    WriteToConsole "--- joining cluster ---"
    WriteToLog "sudo $joincommand"
    Invoke-Expression "sudo $joincommand"

    # sudo kubeadm join --token $token $masterurl --discovery-token-ca-cert-hash $discoverytoken

    WriteToConsole "--- mounting network folder ---"
    MountFolderFromSecrets -baseUrl $baseUrl

    WriteToConsole "This node has successfully joined the cluster"
    
    Stop-Transcript

    return $Return    
}

function SetupMaster([ValidateNotNullOrEmpty()][string] $baseUrl, [bool]$singlenode) {
    [hashtable]$Return = @{} 

    $logfile="$(get-date -f yyyy-MM-dd-HH-mm)-setupmaster.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"
    
    WriteToConsole "--- cleaning up old stuff ---"
    UninstallDockerAndKubernetes
    
    WriteToConsole "--- setting up new node ---"
    SetupNewNode -baseUrl $baseUrl

    WriteToConsole "--- setting up new master node ---"
    SetupNewMasterNode -baseUrl $baseUrl

    if ($singlenode -eq $True) {
        WriteToLog "enabling master node to run containers"
        # enable master to run containers
        # kubectl taint nodes --all node-role.kubernetes.io/master-       
        kubectl taint node --all node-role.kubernetes.io/master:NoSchedule- 
    }
    else {
        mountSharedFolder -saveIntoSecret $True
    }
    
    WriteToConsole "--- setting up load balancer ---"   
    SetupNewLoadBalancer -baseUrl $baseUrl

    WriteToConsole "--- setting up kubernetes dashboard ---"   
    InstallStack -baseUrl $baseUrl -namespace "kube-system" -appfolder "dashboard"
    # clear
    WriteToLog "--- waiting for pods to run in kube-system ---"
    WaitForPodsInNamespace -namespace "kube-system" -interval 5    

    if ($singlenode -eq $True) {
        WriteToLog "Finished setting up a single-node cluster"
    }
    else {
        ShowCommandToJoinCluster $baseUrl    
    }

    Stop-Transcript

    return $Return    
}

function SetupNewMasterNode([ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    $kubernetesversion = "1.10.0"

    $u = "$(whoami)"
    WriteToLog "User name: $u"

    # for calico network plugin
    # WriteToLog "--- running kubeadm init for calico ---"
    # sudo kubeadm init --kubernetes-version=v1.9.6 --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true

    # CLUSTER_DNS_CORE_DNS="true"

    # WriteToLog "--- running kubeadm init for flannel ---"
    # for flannel network plugin
    # sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true
    sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16

    WriteToLog "Troubleshooting kubeadm: https://kubernetes.io/docs/setup/independent/troubleshooting-kubeadm/"

    # which CNI plugin to use: https://chrislovecnm.com/kubernetes/cni/choosing-a-cni-provider/

    # for logs, sudo journalctl -xeu kubelet

    WriteToLog "--- copying kube config to $HOME/.kube/config ---"
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    WriteToLog "sudo chown $(id -u):$(id -g) $HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" $HOME/.kube/config

    # calico
    # from https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/
    # WriteToLog "--- enabling calico network plugin ---"
    # http://leebriggs.co.uk/blog/2017/02/18/kubernetes-networking-calico.html
    # kubectl apply -f ${GITHUB_URL}/kubernetes/cni/calico.yaml

    # flannel
    # kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
    WriteToLog "--- enabling flannel network plugin ---"
    kubectl apply -f ${baseUrl}/kubernetes/cni/flannel.yaml

    WriteToLog "--- sleeping 10 secs to wait for pods ---"
    Start-Sleep 10

    WriteToLog "adding cni0 network interface to trusted zone"
    sudo firewall-cmd --zone=trusted --add-interface cni0 --permanent
    # sudo firewall-cmd --zone=trusted --add-interface docker0 --permanent
    sudo firewall-cmd --reload

    WriteToLog "--- kubelet status ---"
    sudo systemctl status kubelet -l

    # enable master to run containers
    # kubectl taint nodes --all node-role.kubernetes.io/master-

    # kubectl create -f "$GITHUB_URL/azure/cafe-kube-dns.yml"
    WriteToLog "--- nodes ---"
    kubectl get nodes

    WriteToLog "--- sleep for 10 secs ---"
    Start-Sleep 10

    WriteToLog "--- current pods ---"
    kubectl get pods -n kube-system -o wide

    WriteToLog "--- waiting for pods to run ---"
    WaitForPodsInNamespace kube-system 5

    WriteToLog "--- current pods ---"
    kubectl get pods -n kube-system -o wide

    if (!(Test-Path C:\Windows -PathType Leaf)) {
        WriteToLog "--- creating /mnt/data ---"
        sudo mkdir -p "/mnt/data"
        WriteToLog "sudo chown $(id -u):$(id -g) /mnt/data"
        sudo chown "$(id -u):$(id -g)" "/mnt/data"
        sudo chmod -R 777 "/mnt/data"
    }

    WriteToLog "opening port 6661 for mirth"
    sudo firewall-cmd --add-port=6661/tcp --permanent
    WriteToLog "opening port 5671 for rabbitmq"
    sudo firewall-cmd --add-port=5671/tcp --permanent  # flannel networking
    WriteToLog "opening port 3307 for mysql"
    sudo firewall-cmd --add-port 3307/tcp --permanent
    WriteToLog "reloading firewall"
    sudo firewall-cmd --reload
    
    return $Return    
}

function ConfigureFirewall() {
    [hashtable]$Return = @{} 

    WriteToLog " --- installing firewalld ---"
    # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-firewalld-on-centos-7
    sudo yum -y install firewalld
    WriteToLog "--- starting firewalld ---"
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    sudo systemctl status firewalld -l
    WriteToLog "--- removing iptables ---"
    sudo yum -y remove iptables-services

    WriteToLog "Making sure the main network interface is in public zone"
    $primarynic = $(route | grep default | awk '{print $NF; ext }')
    WriteToLog "Found primary network interface: $primarynic"
    if ($primarynic) {
        $zoneforprimarynic = $(sudo firewall-cmd --get-zone-of-interface="$primarynic")
        if (!$zoneforprimarynic) {
            WriteToLog "Primary network interface, $primarynic, was not in any zone so adding it to public zone"
            sudo firewall-cmd --zone=public --add-interface "$primarynic"
            sudo firewall-cmd --permanent --zone=public --add-interface="$primarynic"
            sudo firewall-cmd --reload
        }
        else {
            WriteToLog "Primary network interface, $primarynic, is in $zoneforprimarynic zone"
        }
    }

    WriteToLog "enabling ports in firewalld"
    # https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
    # kubernetes ports: https://kubernetes.io/docs/setup/independent/install-kubeadm/#check-required-ports
    # https://github.com/coreos/coreos-kubernetes/blob/master/Documentation/kubernetes-networking.md
    # https://github.com/coreos/tectonic-docs/blob/master/Documentation/install/rhel/installing-workers.md
    WriteToLog "opening port 22 for SSH"
    sudo firewall-cmd --add-port=22/tcp --permanent # SSH
    WriteToLog "opening port 6443 for Kubernetes API server"
    sudo firewall-cmd --add-port=6443/tcp --permanent # kubernetes API server
    WriteToLog "opening ports 2379-2380 for Kubernetes API server"
    sudo firewall-cmd --add-port=2379-2380/tcp --permanent 
    WriteToLog "opening port 8472,8285 and 4789 for Flannel networking"
    sudo firewall-cmd --add-port=8472/udp --permanent  # flannel networking
    sudo firewall-cmd --add-port=8285/udp --permanent  # flannel networking
    sudo firewall-cmd --add-port 4789/udp --permanent
    WriteToLog "opening ports 10250,10251,10252 and 10255 for Kubelet API"
    sudo firewall-cmd --add-port=10250/tcp --permanent  # Kubelet API
    sudo firewall-cmd --add-port=10251/tcp --permanent 
    sudo firewall-cmd --add-port=10252/tcp --permanent 
    sudo firewall-cmd --add-port=10255/tcp --permanent # Read-only Kubelet API
    WriteToLog "opening ports 80 and 443 for HTTP and HTTPS"
    sudo firewall-cmd --add-port=80/tcp --permanent # HTTP
    sudo firewall-cmd --add-port=443/tcp --permanent # HTTPS
    WriteToLog "Opening port 53 for internal DNS"
    sudo firewall-cmd --add-port=53/udp --permanent # DNS
    sudo firewall-cmd --add-port=53/tcp --permanent # DNS
    sudo firewall-cmd --add-port=67/udp --permanent # DNS
    sudo firewall-cmd --add-port=68/udp --permanent # DNS
    # sudo firewall-cmd --add-port=30000-60000/udp --permanent # NodePort services
    sudo firewall-cmd --add-service=dns --permanent # DNS
    WriteToLog "Adding NTP service to firewall"
    sudo firewall-cmd --add-service=ntp --permanent # NTP server
    WriteToLog "enable all communication between pods"
    # sudo firewall-cmd --zone=trusted --add-interface eth0
    # sudo firewall-cmd --set-default-zone=trusted
    # sudo firewall-cmd --get-zone-of-interface=docker0
    # sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0  
  
    # https://basildoncoder.com/blog/logging-connections-with-firewalld.html
    # sudo firewall-cmd --zone=public --add-rich-rule="rule family="ipv4" source address="198.51.100.0/32" port protocol="tcp" port="10000" log prefix="test-firewalld-log" level="info" accept"
    # sudo tail -f /var/log/messages |grep test-firewalld-log
  
    # WriteToLog "log dropped packets"
    # sudo firewall-cmd  --set-log-denied=all
    
    # flannel settings
    # from https://github.com/kubernetes/contrib/blob/master/ansible/roles/flannel/tasks/firewalld.yml
    # WriteToLog "Open flanneld subnet traffic"
    # sudo firewall-cmd --direct --add-rule ipv4 filter FORWARD 1 -i flannel.1 -j ACCEPT -m comment --comment "flannel subnet"  
  
    # WriteToLog "Save flanneld subnet traffic"
    # sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -i flannel.1 -j ACCEPT -m comment --comment "flannel subnet"
  
    # WriteToLog "Open flanneld to DNAT'ed traffic"
    # sudo firewall-cmd --direct --add-rule ipv4 filter FORWARD 1 -o flannel.1 -j ACCEPT -m comment --comment "flannel subnet"
  
    # WriteToLog "Save flanneld to DNAT'ed traffic"
    # sudo firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 1 -o flannel.1 -j ACCEPT -m comment --comment "flannel subnet"
  
    WriteToLog "--- enable logging of rejected packets ---"
    sudo firewall-cmd --set-log-denied=all
  
    # http://wrightrocket.blogspot.com/2017/11/installing-kubernetes-on-centos-7-with.html
    WriteToLog "reloading firewall"
    sudo firewall-cmd --reload
  
    sudo systemctl status firewalld -l
  
    WriteToLog "--- services enabled in firewall ---"
    sudo firewall-cmd --list-services
    WriteToLog "--- ports enabled in firewall ---"
    sudo firewall-cmd --list-ports
  
    sudo firewall-cmd --list-all

    return $Return        
}
function SetupNewLoadBalancer([ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    # enable running pods on master
    # kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule
    WriteToLog "--- deleting existing resources with label traefik ---"
    kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

    WriteToLog "--- deleting existing service account for traefik ---"
    kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

    $publicip = ""

    AskForSecretValue -secretname "customerid" -prompt "Customer ID "
    WriteToLog "reading secret from kubernetes"
    $customerid = $(ReadSecret -secretname "customerid")

    $fullhostname = $(hostname --fqdn)
    WriteToLog "Full host name of current machine: $fullhostname"
    AskForSecretValue -secretname "dnshostname" -prompt "DNS name used to connect to the master VM (leave empty to use $fullhostname)" -namespace "default" -defaultvalue $fullhostname
    $dnsrecordname = $(ReadSecret -secretname "dnshostname")

    $sslsecret = $(kubectl get secret traefik-cert-ahmn -n kube-system --ignore-not-found=true)

    if (!$sslsecret) {
        $certfolder = Read-Host -Prompt "Location of SSL cert files (tls.crt and tls.key): (leave empty to use self-signed certificates) "

        if (!$certfolder) {
            WriteToLog "Creating self-signed SSL certificate"
            sudo yum -y install openssl
            $u = "$(whoami)"
            $certfolder = "/opt/healthcatalyst/certs"
            WriteToLog "Creating folder: $certfolder and giving access to $u"
            sudo mkdir -p "$certfolder"
            sudo setfacl -m u:$u:rwx "$certfolder"
            rm -rf "$certfolder/*"
            cd "$certfolder"
            # https://gist.github.com/fntlnz/cf14feb5a46b2eda428e000157447309
            WriteToLog "Generating CA cert"
            sudo openssl genrsa -out rootCA.key 2048
            sudo openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -subj /CN=HCKubernetes/O=HealthCatalyst/ -out rootCA.crt
            WriteToLog "Generating certificate for $dnsrecordname"
            sudo openssl genrsa -out tls.key 2048
            sudo openssl req -new -key tls.key -subj /CN=$dnsrecordname/O=HealthCatalyst/ -out tls.csr
            sudo openssl x509 -req -in tls.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out tls.crt -days 3650 -sha256
            sudo cp tls.crt tls.pem
            cd "~"
        }

        ls -al "$certfolder"

        WriteToLog "Deleting any old TLS certs"
        kubectl delete secret traefik-cert-ahmn -n kube-system --ignore-not-found=true

        WriteToLog "Storing TLS certs as kubernetes secret"
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

    WriteToLog "checking if this machine can access a DNS server via host $(hostname)"
    WriteToLog "--- /etc/resolv.conf ---"
    sudo cat /etc/resolv.conf
    WriteToLog "-----------------------"

    $myip = $(host $(hostname) | awk '/has address/ { print $4 ; exit }')

    if (!$myip) {
        throw "Cannot access my DNS server: host $(hostname)"
        WriteToLog "Cannot access my DNS server: host $(hostname)"
        WriteToLog "checking if this machine can access a DNS server via host $(hostname)"
        $myip = $(hostname -I | cut -d" " -f 1)
        if ($myip) {
            WriteToLog "Found an IP via hostname -I: $myip"
        }
    }
    else {
        WriteToLog "My external IP is $myip"
    }

    $dockerversion = "17.03.2.ce-1"
    $kubernetesversion = "1.10.0-0"
    $kubernetescniversion = "0.6.0-0"

    # $(export dockerversion="17.03.2.ce-1")
    # $(export kubernetesversion="1.9.6-0")
    # 1.9.3-0
    # 1.9.6-0
    # 1.10.0-0
    # $(export kubernetescniversion="0.6.0-0")

    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    $u = "$(whoami)"
    WriteToLog "User name: $u"


    ConfigureFirewall
    # ConfigureIpTables

    WriteToConsole "-- starting NTP deamon ---"
    # https://www.tecmint.com/install-ntp-server-in-centos/
    sudo systemctl start ntpd
    sudo systemctl enable ntpd
    sudo systemctl status ntpd -l

    # WriteToConsole "--- stopping docker and kubectl ---"
    # $servicestatus = $(systemctl show -p SubState kubelet)
    # if [[ $servicestatus = *"running"* ]]; then
    # WriteToLog "stopping kubelet"
    # sudo systemctl stop kubelet
    # fi

    # remove older versions
    # sudo systemctl stop docker 2>/dev/null
    WriteToConsole "--- Removing previous versions of kubernetes and docker --"
    if (![string]::IsNullOrEmpty($(command -v kubeadm))) {
        sudo kubeadm reset
    }

    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
    sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
    sudo yum -y remove docker docker-common docker-selinux docker-engine docker-ce docker-ce-selinux
    sudo yum -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine
                    
    # sudo rm -rf /var/lib/docker

    WriteToConsole "--- Adding docker repo --"
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    WriteToConsole " --- current repo list ---"
    sudo yum -y repolist

    WriteToConsole "-- docker versions available in repo --"
    sudo yum -y --showduplicates list docker-ce

    # https://saurabh-deochake.github.io/posts/2017/07/post-1/
    WriteToConsole "setting selinux to disabled so kubernetes can work"
    sudo setenforce 0
    sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    # sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux   

    WriteToConsole "--- Installing docker via yum --"
    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    # need to pass --setpot=obsoletes=0 due to this bug: https://github.com/docker/for-linux/issues/20#issuecomment-312122325
    sudo yum install -y --setopt=obsoletes=0 docker-ce-${dockerversion}.el7.centos docker-ce-selinux-${dockerversion}.el7.centos
    WriteToConsole "--- Locking version of docker so it does not get updated via yum update --"
    sudo yum versionlock add docker-ce
    sudo yum versionlock add docker-ce-selinux

    # https://kubernetes.io/docs/setup/independent/install-kubeadm/
    # log rotation for docker: https://docs.docker.com/config/daemon/
    # https://docs.docker.com/config/containers/logging/json-file/
    WriteToConsole "--- Configuring docker to use systemd and set logs to max size of 10MB and 5 days --"
    sudo mkdir -p /etc/docker
    sudo curl -sSL -o /etc/docker/daemon.json ${baseUrl}/onprem/daemon.json?p=$RANDOM
    
    WriteToConsole "--- Starting docker service --"
    sudo systemctl enable docker
    sudo systemctl start docker

    if ($u -ne "root") {
        WriteToConsole "--- Giving permission to $u to interact with docker ---"
        sudo usermod -aG docker $u
        # reload permissions without requiring a logout
        # from https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
        # https://man.cx/newgrp(1)
        WriteToConsole "--- Reloading permissions via newgrp ---"
        # newgrp docker
    }

    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    WriteToLog "--- docker status ---"
    sudo systemctl status docker -l

    WriteToConsole "--- Adding kubernetes repo ---"
    sudo yum-config-manager --add-repo ${baseUrl}/onprem/kubernetes.repo

    # install kubeadm
    WriteToConsole "--- Removing previous versions of kubernetes ---"
    sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni

    WriteToConsole "--- checking to see if port 10250 is still busy ---"
    sudo lsof -i -P -n | grep LISTEN

    WriteToConsole "--- kubernetes versions available in repo ---"
    sudo yum -y --showduplicates list kubelet kubeadm kubectl kubernetes-cni

    WriteToConsole "--- installing kubernetes ---"
    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    sudo yum install -y "kubelet-${kubernetesversion}" "kubeadm-${kubernetesversion}" "kubectl-${kubernetesversion}" "kubernetes-cni-${kubernetescniversion}"
    WriteToConsole "--- locking versions of kubernetes so they don't get updated by yum update ---"
    sudo yum versionlock add kubelet
    sudo yum versionlock add kubeadm
    sudo yum versionlock add kubectl
    sudo yum versionlock add kubernetes-cni

    WriteToConsole "--- starting kubernetes service ---"
    sudo systemctl enable kubelet
    sudo systemctl start kubelet

    WriteToLog "--- setting up iptables for kubernetes in k8s.conf ---"
    # # Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
    sudo curl -o "/etc/sysctl.d/k8s.conf" -sSL "$baseUrl/onprem/k8s.conf"
    sudo sysctl --system

    WriteToConsole "--- finished setting up node ---"

    return $Return
}

function UninstallDockerAndKubernetes() {
    [hashtable]$Return = @{} 

    $logfile="$(get-date -f yyyy-MM-dd-HH-mm)-uninstall.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    WriteToConsole "Uninstalling docker and kubernetes"

    sudo yum versionlock delete docker-ce
    sudo yum versionlock delete docker-ce-selinux

    sudo yum versionlock delete kubelet
    sudo yum versionlock delete kubeadm
    sudo yum versionlock delete kubectl
    sudo yum versionlock delete kubernetes-cni
    
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

    WriteToConsole "Successfully uninstalled docker and kubernetes"

    Stop-Transcript
    
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
        WriteToLog "User will mount a shared folder manually"
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

    mountSMBWithParams -pathToShare $pathToShare -username $username -domain $domain -password $password -saveIntoSecret $saveIntoSecret -isUNC $True

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

function MountFolderFromSecrets([ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 
    WriteToConsole "--- waiting to let kubernetes come up ---"
    Do {
        Write-Host '.' -NoNewline;
        Start-Sleep -Seconds 5;
    } while (!(Test-Path -Path "/etc/kubernetes/kubelet.conf"))

    Start-Sleep -Seconds 10

    WriteToConsole "--- copying kube config to ${HOME}/.kube/config ---"
    mkdir -p "${HOME}/.kube"
    sudo cp -f "/etc/kubernetes/kubelet.conf" "${HOME}/.kube/config"
    sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"

    WriteToConsole "--- giving read access to current user to /var/lib/kubelet/pki/kubelet-client.key ---"
    $u = "$(whoami)"
    sudo setfacl -m u:${u}:r "/var/lib/kubelet/pki/kubelet-client.key"

    WriteToConsole "--- reading secret for folder to mount ----"

    $secretname = "mountsharedfolder"
    $namespace = "default"    
    $pathToShare = $(ReadSecretValue -secretname $secretname -valueName "path" -namespace $namespace)
    $username = $(ReadSecretValue -secretname $secretname -valueName "username" -namespace $namespace)
    $domain = $(ReadSecretValue -secretname $secretname -valueName "domain" -namespace $namespace)
    $password = $(ReadSecretValue -secretname $secretname -valueName "password" -namespace $namespace)

    if ($username) {
        mountSMBWithParams -pathToShare $pathToShare -username $username -domain $domain -password $password -saveIntoSecret $False -isUNC $True
    }
    else {
        WriteToLog "No username found in secrets"
        mountSMB -saveIntoSecret $False
    }
    return $Return    
}

function mountSMBWithParams([ValidateNotNullOrEmpty()][string] $pathToShare, [ValidateNotNullOrEmpty()][string] $username, [ValidateNotNullOrEmpty()][string] $domain, [ValidateNotNullOrEmpty()][string] $password, [ValidateNotNullOrEmpty()][bool] $saveIntoSecret, [ValidateNotNullOrEmpty()][bool] $isUNC) {
    [hashtable]$Return = @{} 
    $passwordlength = $($password.length)
    WriteToLog "mounting file share with path: [$pathToShare], user: [$username], domain: [$domain], password_length: [$passwordlength] saveIntoSecret: [$saveIntoSecret], isUNC: [$isUNC]"
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

    if ($isUNC -eq $True) {
        WriteToLog "Mounting as UNC folder"
        WriteToLog "sudo mount --verbose -t cifs $pathToShare /mnt/data -o vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm"
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o "vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm"
        WriteToLog "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm" | sudo tee -a /etc/fstab > /dev/null
    }
    else {
        WriteToLog "Mounting as non-UNC folder"
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o "vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino"
        WriteToLog "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab > /dev/null       
    }

    WriteToLog "--- Mounting all shares ---"
    sudo mount -a --verbose

    if ( $saveIntoSecret -eq $True) {
        WriteToLog "Saving mount information into a secret"
        $secretname = "mountsharedfolder"
        $namespace = "default"
        if ([string]::IsNullOrEmpty("$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)")) {
            kubectl delete secret $secretname --namespace=$namespace
        }
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=path=$pathToShare --from-literal=username=$username --from-literal=domain=$domain --from-literal=password=$password 
    }

    touch "/mnt/data/$(hostname).txt"

    WriteToLog "Listing files in shared folder"
    ls -al /mnt/data
    return $Return    
}

function ShowCommandToJoinCluster([ValidateNotNullOrEmpty()][string] $baseUrl) {
    
    $joinCommand = $(sudo kubeadm token create --print-join-command)
    if ($joinCommand) {
        # $parts = $joinCommand.Split(' ');
        # $masterurl = $parts[2];
        # $token = $parts[4];
        # $discoverytoken = $parts[6];
    
        WriteToLog "Run this command on any new node to join this cluster (this command expires in 24 hours):"
        WriteToLog "---- COPY BELOW THIS LINE ----"
        WriteToLog "curl -sSL $baseUrl/onprem/setupnode.sh?p=`$RANDOM -o setupnode.sh; bash setupnode.sh `"$joinCommand`""
    
        # if [[ ! -z "$pathToShare" ]]; then
        #     WriteToLog "curl -sSL $baseUrl/onprem/mountfolder.sh?p=$RANDOM | bash -s $pathToShare $username $domain $password 2>&1 | tee mountfolder.log"
        # fi
        # WriteToLog "sudo $(sudo kubeadm token create --print-join-command)"
        WriteToLog ""
        WriteToLog "---- COPY ABOVE THIS LINE ----"
    }
}

# --------------------
Write-Information -MessageData "end common-onprem.ps1 version $versiononpremcommon"