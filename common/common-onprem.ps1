$versiononpremcommon = "2018.05.21.05"

Write-Information -MessageData "Including common-onprem.ps1 version $versiononpremcommon"
function global:GetCommonOnPremVersion() {
    return $versiononpremcommon
}

$dockerversion = "17.03.2.ce-1"
$kubernetesversion = "1.10.0-0"
$kubernetescniversion = "0.6.0-0"
$kubernetesserverversion = "1.10.0"

function SetupWorker([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl, [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $joincommand) {
    [hashtable]$Return = @{} 
    
    # Set-PSDebug -Trace 1   
    $logfile = "$(get-date -f yyyy-MM-dd-HH-mm)-setupworker.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    WriteToConsole "cleaning up old stuff"
    UninstallDockerAndKubernetes

    WriteToConsole "setting up new node"
    SetupNewNode -baseUrl $baseUrl

    WriteToConsole "joining cluster"
    WriteToLog "sudo $joincommand"
    Invoke-Expression "sudo $joincommand"

    # sudo kubeadm join --token $token $masterurl --discovery-token-ca-cert-hash $discoverytoken

    WriteToConsole "mounting network folder"
    MountFolderFromSecrets -baseUrl $baseUrl

    WriteToConsole "This node has successfully joined the cluster"

    kubectl get nodes
    
    Stop-Transcript

    return $Return    
}

function SetupMaster([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl, [bool]$singlenode) {
    [hashtable]$Return = @{} 

    $logfile = "$(get-date -f yyyy-MM-dd-HH-mm)-setupmaster.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"
    
    WriteToConsole "cleaning up old stuff"
    UninstallDockerAndKubernetes
    
    WriteToConsole "setting up new node"
    SetupNewNode -baseUrl $baseUrl

    WriteToConsole "setting up new master node"
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
    
    WriteToConsole "setting up load balancer"   
    SetupNewLoadBalancer -baseUrl $baseUrl

    WriteToConsole "setting up kubernetes dashboard"   
    InstallStack -baseUrl $baseUrl -namespace "kube-system" -appfolder "dashboard"
    # clear
    WriteToLog "waiting for pods to run in kube-system"
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

function SetupNewMasterNode([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl) {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingCmdletAliases", "", Justification="We're calling linux commands")]

    [hashtable]$Return = @{} 

    $u = "$(whoami)"
    WriteToLog "User name: $u"

    # for calico network plugin
    # WriteToLog "running kubeadm init for calico"
    # sudo kubeadm init --kubernetes-version=v1.9.6 --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true

    # CLUSTER_DNS_CORE_DNS="true"

    # WriteToLog "running kubeadm init for flannel"
    # for flannel network plugin
    # sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=10.244.0.0/16 --feature-gates CoreDNS=true
    # https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
    sudo kubeadm init --kubernetes-version=v${kubernetesserverversion} --pod-network-cidr=10.244.0.0/16 --skip-token-print --apiserver-cert-extra-sans $(hostname --fqdn)
    $result = $?
    if($result -ne $True){
        throw "Error running kubeadm init"
    }

    WriteToLog "Troubleshooting kubeadm: https://kubernetes.io/docs/setup/independent/troubleshooting-kubeadm/"

    # which CNI plugin to use: https://chrislovecnm.com/kubernetes/cni/choosing-a-cni-provider/

    # for logs, sudo journalctl -xeu kubelet

    WriteToLog "copying kube config to $HOME/.kube/config"
    mkdir -p $HOME/.kube
    sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
    WriteToLog "sudo chown $(id -u):$(id -g) $HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" $HOME/.kube/config

    # calico
    # from https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/
    # WriteToLog "enabling calico network plugin"
    # http://leebriggs.co.uk/blog/2017/02/18/kubernetes-networking-calico.html
    # kubectl apply -f ${baseUrl}/kubernetes/cni/calico.yaml

    # flannel
    # kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
    WriteToLog "enabling flannel network plugin"
    kubectl apply -f ${baseUrl}/kubernetes/cni/flannel.yaml

    WriteToLog "sleeping 10 secs to wait for pods"
    Start-Sleep 10

    WriteToLog "adding cni0 network interface to trusted zone"
    sudo firewall-cmd --zone=trusted --add-interface cni0 --permanent
    # sudo firewall-cmd --zone=trusted --add-interface docker0 --permanent
    sudo firewall-cmd --reload

    WriteToLog "kubelet status"
    sudo systemctl status kubelet -l

    # enable master to run containers
    # kubectl taint nodes --all node-role.kubernetes.io/master-

    # kubectl create -f "${baseUrl}/azure/cafe-kube-dns.yml"
    WriteToLog "nodes"
    kubectl get nodes

    WriteToLog "sleep for 10 secs"
    Start-Sleep 10

    WriteToLog "current pods"
    kubectl get pods -n kube-system -o wide

    WriteToLog "waiting for pods to run"
    WaitForPodsInNamespace kube-system 5

    WriteToLog "current pods"
    kubectl get pods -n kube-system -o wide

    if (!(Test-Path C:\Windows -PathType Leaf)) {
        WriteToLog "creating /mnt/data"
        sudo mkdir -p "/mnt/data"
        WriteToLog "sudo chown $(id -u):$(id -g) /mnt/data"
        sudo chown "$(id -u):$(id -g)" "/mnt/data"
        sudo chmod -R 777 "/mnt/data"
    }

    AddFirewallPort -port "6661/tcp" -name "Mirth"
    AddFirewallPort -port "5671/tcp" -name "RabbitMq"
    AddFirewallPort -port "3307/tcp" -name "MySql"

    WriteToLog "reloading firewall"
    sudo firewall-cmd --reload

    WriteToLog "enabling autocomplete for kubectl"
    echo "source <(kubectl completion bash)" >> ~/.bashrc
    
    return $Return    
}

function ConfigureIpTables() {
    WriteToConsole "switching from firewalld to iptables"
    # iptables-services: for iptables firewall  
    sudo yum -y install iptables-services
    # https://www.digitalocean.com/community/tutorials/how-to-migrate-from-firewalld-to-iptables-on-centos-7
    sudo systemctl stop firewalld
    sudo systemctl start iptables; 
    # sudo systemctl start ip6tables
    # sudo firewall-cmd --state
    sudo systemctl disable firewalld
    sudo systemctl enable iptables
    # sudo systemctl enable ip6tables
  
    WriteToConsole "removing firewalld"
    sudo yum -y remove firewalld
    
    WriteToConsole "setting up iptables rules"
    # https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands
    WriteToConsole "fixing kubedns"
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -I INPUT -p tcp -m tcp --dport 8472 -j ACCEPT
    sudo iptables -I INPUT -p tcp -m tcp --dport 6443 -j ACCEPT
    sudo iptables -I INPUT -p tcp -m tcp --dport 9898 -j ACCEPT
    sudo iptables -I INPUT -p tcp -m tcp --dport 10250 -j ACCEPT  
    sudo iptables -I INPUT -p tcp -m tcp --dport 443 -j ACCEPT  
    sudo iptables -I INPUT -p tcp -m tcp --dport 8081 -j ACCEPT  
    # WriteToConsole "allow all outgoing connections"
    # sudo iptables -I OUTPUT -o eth0 -d 0.0.0.0/0 -j ACCEPT
    WriteToConsole "allowing loopback connections"
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A OUTPUT -o lo -j ACCEPT
    WriteToConsole "allowing established and related incoming connections"
    sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED, RELATED -j ACCEPT
    WriteToConsole "allowing established outgoing connections"
    sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
    WriteToConsole "allowing docker containers to access the external network"
    sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
    sudo iptables -A FORWARD -i docker0 -o eth0 -j ACCEPT
    WriteToConsole "allow all incoming ssh"
    sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW, ESTABLISHED -j ACCEPT
    sudo iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
    # reject an IP address
    # sudo iptables -A INPUT -s 15.15.15.51 -j REJECT
    WriteToConsole "allow incoming HTTP"
    sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW, ESTABLISHED -j ACCEPT
    sudo iptables -A OUTPUT -p tcp --sport 80 -m conntrack --ctstate ESTABLISHED -j ACCEPT
    WriteToConsole "allow incoming HTTPS"
    sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW, ESTABLISHED -j ACCEPT
    sudo iptables -A OUTPUT -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT
    #WriteToConsole "block outgoing SMTP Mail"
    #sudo iptables -A OUTPUT -p tcp --dport 25 -j REJECT
    
    WriteToConsole "reloading iptables"
    sudo systemctl reload iptables
    # WriteToConsole "saving iptables"
    # sudo iptables-save
    # WriteToConsole "restarting iptables"
    # sudo systemctl restart iptables
    WriteToConsole "status of iptables "
    sudo systemctl status iptables
    WriteToConsole "current iptables rules"
    sudo iptables -t nat -L
}
  
function AddFirewallPort([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$port, [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $name) {
    if ("$(sudo firewall-cmd --query-port=${port})" -ne "yes") {
        WriteToLog "opening port $port for $name"
        sudo firewall-cmd --add-port=${port} --permanent
    }
    else {
        WriteToLog "Port $port for $name is already open"
    }
}
function ConfigureFirewall() {
    [hashtable]$Return = @{} 

    WriteToLog " installing firewalld"
    # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-firewalld-on-centos-7
    sudo yum -y install firewalld
    WriteToLog "starting firewalld"
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    sudo systemctl status firewalld -l
    WriteToLog "removing iptables"
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
    AddFirewallPort -port "22/tcp" -name "SSH"
    AddFirewallPort -port "6443/tcp" -name "Kubernetes API server"
    AddFirewallPort -port "80/tcp" -name "HTTP"
    AddFirewallPort -port "443/tcp" -name "HTTPS"
    AddFirewallPort -port "2379-2380/tcp" -name "Flannel networking"
    AddFirewallPort -port "8472/udp" -name "Flannel networking"
    AddFirewallPort -port "8285/udp" -name "Flannel networking"
    AddFirewallPort -port "4789/udp" -name "Flannel networking"
    AddFirewallPort -port "10250-10255/tcp" -name "Kubelet API"
    # WriteToLog "Opening port 53 for internal DNS"
    # AddFirewallPort -port "443/tcp" -name "DNS"
    # sudo firewall-cmd --add-port=53/udp --permanent # DNS
    # AddFirewallPort -port "443/tcp" -name "HTTPS"
    # sudo firewall-cmd --add-port=53/tcp --permanent # DNS
    # AddFirewallPort -port "443/tcp" -name "HTTPS"
    # sudo firewall-cmd --add-port=67/udp --permanent # DNS
    # AddFirewallPort -port "443/tcp" -name "HTTPS"
    # sudo firewall-cmd --add-port=68/udp --permanent # DNS
    # # sudo firewall-cmd --add-port=30000-60000/udp --permanent # NodePort services
    # sudo firewall-cmd --add-service=dns --permanent # DNS
    # WriteToLog "Adding NTP service to firewall"
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
  
    WriteToLog "enable logging of rejected packets"
    sudo firewall-cmd --set-log-denied=all
  
    # http://wrightrocket.blogspot.com/2017/11/installing-kubernetes-on-centos-7-with.html
    WriteToLog "reloading firewall"
    sudo firewall-cmd --reload
  
    sudo systemctl status firewalld -l
  
    WriteToLog "services enabled in firewall"
    sudo firewall-cmd --list-services
    WriteToLog "ports enabled in firewall"
    sudo firewall-cmd --list-ports
  
    sudo firewall-cmd --list-all

    return $Return        
}
function SetupNewLoadBalancer([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    WriteToConsole "deleting any old resources"
    # enable running pods on master
    # kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule
    WriteToLog "deleting existing resources with label traefik"
    kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

    WriteToLog "deleting existing service account for traefik"
    kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

    $publicip = ""

    AskForSecretValue -secretname "customerid" -prompt "Customer ID "
    WriteToLog "reading secret from kubernetes"
    $customerid = $(ReadSecretValue -secretname "customerid")

    $fullhostname = $(hostname --fqdn)
    WriteToLog "Full host name of current machine: $fullhostname"
    AskForSecretValue -secretname "dnshostname" -prompt "DNS name used to connect to the master VM (leave empty to use $fullhostname)" -namespace "default" -defaultvalue $fullhostname
    $dnsrecordname = $(ReadSecretValue -secretname "dnshostname")

    $sslsecret = $(kubectl get secret traefik-cert-ahmn -n kube-system --ignore-not-found=true)

    if (!$sslsecret) {
        $certfolder = Read-Host -Prompt "Location of SSL cert files (tls.crt and tls.key): (leave empty to generate self-signed certificates)"

        if (!$certfolder) {
            WriteToLog "Generating self-signed SSL certificate"
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

    $ingressInternalType = "public"
    $ingressExternalType = "onprem"
    $externalIp = ""
    $internalIp = ""

    LoadLoadBalancerStack -baseUrl $baseUrl -ssl 1 -customerid $customerid `
                        -ingressInternalType $ingressInternalType -ingressExternalType $ingressExternalType `
                        -isOnPrem $true `
                        -externalSubnetName "" -externalIp "$externalIp" `
                        -internalSubnetName "" -internalIp "$internalIp"

    return $Return
}

function SetupNewNode([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 

    WriteToLog "checking if this machine can access a DNS server via host $(hostname)"
    WriteToLog "/etc/resolv.conf"
    sudo cat /etc/resolv.conf
    WriteToLog "----------------------------"

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

    WriteToConsole "starting NTP deamon"
    # https://www.tecmint.com/install-ntp-server-in-centos/
    sudo systemctl start ntpd
    sudo systemctl enable ntpd
    sudo systemctl status ntpd -l

    # WriteToConsole "stopping docker and kubectl"
    # $servicestatus = $(systemctl show -p SubState kubelet)
    # if [[ $servicestatus = *"running"* ]]; then
    # WriteToLog "stopping kubelet"
    # sudo systemctl stop kubelet
    # fi

    # remove older versions
    UninstallDockerAndKubernetes
                    
    WriteToConsole "Adding docker repo "
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    WriteToConsole " current repo list"
    sudo yum -y repolist

    WriteToConsole "docker versions available in repo "
    sudo yum -y --showduplicates list docker-ce
    sudo yum -y --showduplicates list docker-ce-selinux

    # https://saurabh-deochake.github.io/posts/2017/07/post-1/
    WriteToConsole "setting selinux to disabled so kubernetes can work"
    sudo setenforce 0
    sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    # sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux   

    WriteToConsole "Installing docker via yum "
    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    # need to pass --setpot=obsoletes=0 due to this bug: https://github.com/docker/for-linux/issues/20#issuecomment-312122325
    sudo yum install -y --setopt=obsoletes=0 docker-ce-${dockerversion}.el7.centos docker-ce-selinux-${dockerversion}.el7.centos
    # installYumPackages "docker-ce-${dockerversion}.el7.centos docker-ce-selinux-${dockerversion}.el7.centos"
    lockPackageVersion "docker-ce docker-ce-selinux"

    # https://kubernetes.io/docs/setup/independent/install-kubeadm/
    # log rotation for docker: https://docs.docker.com/config/daemon/
    # https://docs.docker.com/config/containers/logging/json-file/
    WriteToConsole "Configuring docker to use systemd and set logs to max size of 10MB and 5 days "
    sudo mkdir -p /etc/docker
    sudo curl -sSL -o /etc/docker/daemon.json ${baseUrl}/onprem/daemon.json?p=$RANDOM
    
    WriteToConsole "Starting docker service "
    sudo systemctl enable docker
    sudo systemctl start docker

    if ($u -ne "root") {
        WriteToConsole "Giving permission to $u to interact with docker"
        sudo usermod -aG docker $u
        # reload permissions without requiring a logout
        # from https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
        # https://man.cx/newgrp(1)
        WriteToConsole "Reloading permissions via newgrp"
        # newgrp docker
    }

    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"

    WriteToLog "docker status"
    sudo systemctl status docker -l

    WriteToConsole "Adding kubernetes repo"
    sudo yum-config-manager --add-repo ${baseUrl}/onprem/kubernetes.repo

    WriteToConsole "checking to see if port 10250 is still busy"
    sudo lsof -i -P -n | grep LISTEN

    WriteToConsole "kubernetes versions available in repo"
    sudo yum -y --showduplicates list kubelet kubeadm kubectl kubernetes-cni

    WriteToConsole "installing kubernetes"
    WriteToLog "using docker version ${dockerversion}, kubernetes version ${kubernetesversion}, cni version ${kubernetescniversion}"
    sudo yum -y install kubelet-${kubernetesversion} kubeadm-${kubernetesversion} kubectl-${kubernetesversion} kubernetes-cni-${kubernetescniversion}
    lockPackageVersion "kubelet kubeadm kubectl kubernetes-cni"
    WriteToConsole "locking versions of kubernetes so they don't get updated by yum update"
    # sudo yum versionlock add kubelet
    # sudo yum versionlock add kubeadm
    # sudo yum versionlock add kubectl
    # sudo yum versionlock add kubernetes-cni

    WriteToConsole "starting kubernetes service"
    sudo systemctl enable kubelet
    sudo systemctl start kubelet

    WriteToLog "setting up iptables for kubernetes in k8s.conf"
    # # Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
    sudo curl -o "/etc/sysctl.d/k8s.conf" -sSL "$baseUrl/onprem/k8s.conf"
    sudo sysctl --system

    WriteToConsole "finished setting up node"

    return $Return
}

function UninstallDockerAndKubernetes() {
    [hashtable]$Return = @{} 

    $logfile = "$(get-date -f yyyy-MM-dd-HH-mm)-uninstall.txt"
    WriteToConsole "Logging to $logfile"
    Start-Transcript -Path "$logfile"

    WriteToConsole "Uninstalling docker and kubernetes"
   
    if ("$(command -v kubeadm)") {
        WriteToLog "resetting kubeadm"
        sudo kubeadm reset
    }    
    sudo yum -y remove kubelet kubeadm kubectl kubernetes-cni
    unlockPackageVersion "kubelet kubeadm kubectl kubernetes-cni"

    if ("$(command -v docker)") {
        sudo docker system prune -f
        # sudo docker volume rm etcd
    }
    sudo rm -rf /var/etcd/backups/*
    sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
    sudo yum -y remove docker docker-common docker-selinux docker-engine docker-ce docker-ce-selinux container-selinux
    sudo yum -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine
    unlockPackageVersion "docker-ce docker-ce-selinux"

    WriteToConsole "Successfully uninstalled docker and kubernetes"

    Stop-Transcript

    return $Return
}

function lockPackageVersion([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$packagelist) {
    $packages = $packagelist.Split(" ");
    foreach ($name in $packages) {
        sudo yum list installed $name 
        if (!($?)) {
            sudo yum versionlock add $name 2>&1 >> yum.log
        }
    }
}
function unlockPackageVersion([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$packagelist) {
    $packages = $packagelist.Split(" ");
    foreach ($name in $packages) {
        sudo yum versionlock delete $name 2>&1 >> yum.log
    }
}

function mountSharedFolder([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][bool] $saveIntoSecret) {
    [hashtable]$Return = @{} 

    Write-Host "DOS requires a network folder that can be accessed from all the worker VMs"
    Write-Host "1. Mount an existing Azure file share"
    Write-Host "2. Mount an existing UNC network file share"
    Write-Host "3. I've already mounted a shared folder at /mnt/data/"
    Write-Host ""

    $inputArray = @(1,2,3)

    Do {$mountChoice = Read-Host -Prompt "Choose a number"} while (!$mountChoice -or ($inputArray -notcontains $mountChoice))

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

function mountSMB([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][bool] $saveIntoSecret) {
    [hashtable]$Return = @{} 

    Do {$pathToShare = Read-Host -Prompt "path to SMB share (e.g., //myserver.mydomain/myshare)"} while (!$pathToShare)

    # convert to unix style since that's what linux mount command expects
    $pathToShare = ($pathToShare -replace "\\", "/")
 
    Do {$domain = Read-Host -Prompt "domain"} while (!$domain)

    Do {$username = Read-Host -Prompt "username"} while (!$username)

    Do {$password = Read-Host -assecurestring -Prompt "password"} while ($($password.Length) -lt 1)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

    mountSMBWithParams -pathToShare $pathToShare -username $username -domain $domain -password $password -saveIntoSecret $saveIntoSecret -isUNC $True

    return $Return    

}

function mountAzureFile([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][bool] $saveIntoSecret) {
    [hashtable]$Return = @{} 
    
    Do {$storageAccountName = Read-Host -Prompt "Storage Account Name"} while (!$storageAccountName)

    Do {$shareName = Read-Host -Prompt "Storage Share Name"} while (!$shareName)

    $pathToShare = "//${storageAccountName}.file.core.windows.net/${shareName}"
    $username = "$storageAccountName"

    Do {$storageAccountKey = Read-Host -Prompt "storage account key"} while (!$storageAccountKey)

    mountSMBWithParams -pathToShare $pathToShare -username $username -domain "domain" -password $storageAccountKey -saveIntoSecret $saveIntoSecret -isUNC $False
    return $Return    
}

function MountFolderFromSecrets([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl) {
    [hashtable]$Return = @{} 
    WriteToConsole "waiting to let kubernetes come up"
    Do {
        Write-Host '.' -NoNewline;
        Start-Sleep -Seconds 5;
    } while (!(Test-Path -Path "/etc/kubernetes/kubelet.conf"))

    Start-Sleep -Seconds 10

    WriteToConsole "copying kube config to ${HOME}/.kube/config"
    mkdir -p "${HOME}/.kube"
    sudo cp -f "/etc/kubernetes/kubelet.conf" "${HOME}/.kube/config"
    sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/config"

    WriteToConsole "giving read access to current user to /var/lib/kubelet/pki/kubelet-client.key"
    $u = "$(whoami)"
    sudo setfacl -m u:${u}:r "/var/lib/kubelet/pki/kubelet-client.key"

    WriteToConsole "reading secret for folder to mount "

    $secretname = "mountsharedfolder"
    $namespace = "default"    
    $pathToShare = $(ReadSecretData -secretname $secretname -valueName "path" -namespace $namespace)
    $username = $(ReadSecretData -secretname $secretname -valueName "username" -namespace $namespace)
    $domain = $(ReadSecretData -secretname $secretname -valueName "domain" -namespace $namespace)
    $password = $(ReadSecretData -secretname $secretname -valueName "password" -namespace $namespace)

    if ($username) {
        mountSMBWithParams -pathToShare $pathToShare -username $username -domain $domain -password $password -saveIntoSecret $False -isUNC $True
    }
    else {
        WriteToLog "No username found in secrets"
        mountSMB -saveIntoSecret $False
    }
    return $Return    
}

function mountSMBWithParams([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $pathToShare, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $username, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $domain, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $password, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][bool] $saveIntoSecret, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][bool] $isUNC) {
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
        WriteToLog "sudo mount --verbose -t cifs $pathToShare /mnt/data -o username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm"
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o "username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm"
        $result=$?
        if($result -ne $true){
            throw "Unable to mount $pathToShare with username=$username,domain=$domain"
        }
        echo "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,domain=$domain,password=$password,dir_mode=0777,file_mode=0777,sec=ntlm" | sudo tee -a /etc/fstab > /dev/null
    }
    else {
        WriteToLog "Mounting as non-UNC folder"
        sudo mount --verbose -t cifs $pathToShare /mnt/data -o "username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino"
        $result=$?
        if($result -ne $true){
            throw "Unable to mount $pathToShare with username=$username"
        }
        echo "$pathToShare /mnt/data cifs nofail,vers=2.1,username=$username,password=$password,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab > /dev/null       
    }

    WriteToLog "Mounting all shares"
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

function ShowCommandToJoinCluster([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl, [bool]$prerelease) {
    
    $joinCommand = $(sudo kubeadm token create --print-join-command)
    if ($joinCommand) {
        # $parts = $joinCommand.Split(' ');
        # $masterurl = $parts[2];
        # $token = $parts[4];
        # $discoverytoken = $parts[6];
    
        WriteToConsole "Run this command on any new node to join this cluster (this command expires in 24 hours):"
        WriteToConsole "---------------- COPY BELOW THIS LINE ----------------"
        $fullCommand= "curl -sSL $baseUrl/onprem/setupworker.sh?p=`$RANDOM -o setupworker.sh; bash setupworker.sh `"$joinCommand`""
        if($prerelease){
            $fullCommand = "${fullCommand} -prerelease"
        }
        WriteToConsole $fullCommand
    
        # if [[ ! -z "$pathToShare" ]]; then
        #     WriteToLog "curl -sSL $baseUrl/onprem/mountfolder.sh?p=$RANDOM | bash -s $pathToShare $username $domain $password 2>&1 | tee mountfolder.log"
        # fi
        # WriteToLog "sudo $(sudo kubeadm token create --print-join-command)"
        WriteToLog ""
        WriteToLog "-------------------- COPY ABOVE THIS LINE ------------------------------"
    }
}

function OptimizeCentosForHyperv() {
    # from https://www.altaro.com/hyper-v/centos-linux-hyper-v/
    WriteToConsole "installing hyperv-daemons package"
    sudo yum install -y hyperv-daemons bind-utils
    WriteToConsole "turning off disk optimization in centos since Hyper-V already does disk optimization"
    # don't use WriteToConsole here
    echo "noop" | sudo tee /sys/block/sda/queue/scheduler
    $myip = $(host $(hostname) | awk '/has address/ { print $4 ; exit }')
    WriteToConsole "You can connect to this machine via SSH: ssh $(whoami)@${myip}"
    # grep -v "$(hostname)" /etc/hosts | sudo tee /etc/hosts > /dev/null
    # WriteToConsole "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts > /dev/null    
}

function TroubleshootNetworking() {
    # https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
    WriteToConsole " open ports " 
    sudo nmap 127.0.0.1
    WriteToConsole "network interfaces "
    sudo ip link show
    WriteToConsole "services enabled in firewall"
    sudo firewall-cmd --list-services
    WriteToConsole "ports enabled in firewall"
    sudo firewall-cmd --list-ports
    WriteToConsole "active zones"
    sudo firewall-cmd --get-active-zones
    WriteToConsole "available services to enable"
    sudo firewall-cmd --get-services
    WriteToConsole "all rules in firewall"
    sudo firewall-cmd --list-all
    sudo firewall-cmd --zone trusted --list-all
    WriteToConsole "iptables --list"
    sudo iptables --list
    WriteToConsole "checking DNS server "
    $ipfordnsservice = $(kubectl get svc kube-dns -n kube-system -o jsonpath="{.spec.clusterIP}")
    sudo dig "@${ipfordnsservice}" kubernetes.default.svc.cluster.local +noall +answer
    sudo dig "@${ipfordnsservice}" ptr 1.0.96.10.in-addr.arpa. +noall +answer
    WriteToConsole "recent rejected packets "
    sudo tail --lines 1000 /var/log/messages | grep REJECT
}

function TestDNS([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $baseUrl) {
    WriteToConsole "To resolve DNS issues: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#debugging-dns-resolution"
    WriteToConsole "Checking if DNS pods are running"
    kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o wide
    WriteToConsole "Details about DNS pods"
    kubectl describe pods --namespace=kube-system -l k8s-app=kube-dns    
    WriteToConsole "Details about flannel pods"
    kubectl logs --namespace kube-system -l app=flannel
    WriteToConsole "Checking if DNS service is running"
    kubectl get svc --namespace=kube-system
    WriteToConsole "Checking if DNS endpoints are exposed "
    kubectl get ep kube-dns --namespace=kube-system
    WriteToConsole "Checking logs for DNS service"
    # kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name)
    kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c kubedns
    kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c dnsmasq
    kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c sidecar        
    WriteToConsole "Creating a busybox pod to test DNS"
    Do {
        WriteToConsole "Waiting for busybox to terminate"
        WriteToConsole "."
        Start-Sleep 5
    } while ($(kubectl get pods busybox -n default -o jsonpath='{.status.phase}' --ignore-not-found=true))

    kubectl create -f $baseUrl/kubernetes/test/busybox.yaml
    Do {    
        WriteToConsole "."
        Start-Sleep 5
    } while ("$(kubectl get pods busybox -n default -o jsonpath='{.status.phase}')" -ne "Running")
    WriteToConsole " resolve.conf "
    kubectl exec busybox cat /etc/resolv.conf
    WriteToConsole "testing if we can access internal (pod) network"
    kubectl exec busybox nslookup kubernetes.default
    WriteToConsole "testing if we can access external network"
    kubectl exec busybox wget www.google.com
    kubectl delete -f $baseUrl/kubernetes/test/busybox.yaml    
    WriteToConsole "firewall logs"
    sudo systemctl status firewalld -l
}

function ShowContentsOfSharedFolder() {
    ls -al /mnt/data
}

function OpenKubernetesDashboard() {
    $dnshostname = $(ReadSecretValue "dnshostname")
    $myip = $(host $(hostname) | awk '/has address/ { print $4 ; exit }')
    WriteToConsole "dns entries for c:\windows\system32\drivers\etc\hosts (if needed)"
    WriteToConsole "${myip} ${dnshostname}"
    WriteToConsole "-"
    WriteToConsole "You can access the kubernetes dashboard at: https://${dnshostname}/api/ or https://${myip}/api/"
    $secretname = $(kubectl -n kube-system get secret | grep api-dashboard-user | awk '{print $1}')
    $token = $(ReadSecretData "$secretname" "token" "kube-system")
    WriteToConsole "Bearer Token"
    WriteToConsole $token
    WriteToConsole " End of Bearer Token -"
}

function OpenTraefikDashboard() {
    $dnshostname = $(ReadSecretValue "dnshostname")
    $myip = $(host $(hostname) | awk '/has address/ { print $4 ; exit }')
    WriteToConsole "dns entries for c:\windows\system32\drivers\etc\hosts (if needed)"
    WriteToConsole "${myip} ${dnshostname}"
    WriteToConsole "-"
    WriteToConsole "You can access the traefik dashboard at: https://${dnshostname}/external/ or https://${myip}/external/"
    WriteToConsole "You can access the traefik dashboard at: https://${dnshostname}/internal/ or https://${myip}/internal/"
}
function ShowKubernetesServiceStatus() {
    sudo systemctl status kubelet -l
    sudo journalctl -xe --priority 0..3
    sudo journalctl -u kube-apiserve
}

function OpenPortOnPrem([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][number]$port, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$name, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$protocol, `
                        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$type) 
{
    AddFirewallPort -port "${port}/${protocol}" -name "$name"
}
# 
Write-Information -MessageData "end common-onprem.ps1 version $versiononpremcommon"