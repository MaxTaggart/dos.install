$versiononpremcommon = "2018.04.16.03"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Information -MessageData "Including common-onprem.ps1 version $versionkubecommon"
function global:GetCommonOnPremVersion() {
    return $versiononpremcommon
}

function WriteOut($txt) {
    Write-Information -MessageData "$txt"
}

function Write-Status($txt) {
    Write-Information -MessageData "$txt"
}

function SetupMaster([ValidateNotNullOrEmpty()] $baseUrl, $singlenode) {
    [hashtable]$Return = @{} 
    
    SetupNewNode $baseUrl
    SetupNewMasterNode $baseUrl 
    if ($singlenode -eq $true) {
        WriteOut "enabling master node to run containers"
        # enable master to run containers
        # kubectl taint nodes --all node-role.kubernetes.io/master-       
        kubectl taint node --all node-role.kubernetes.io/master:NoSchedule- 
    }
    else {
        mountSharedFolder true
    }
    # cannot use tee here because it calls a ps1 file
    SetupNewLoadBalancer $baseUrl

    InstallStack $baseUrl "kube-system" "dashboard"
    # clear
    WriteOut "--- waiting for pods to run ---"
    WaitForPodsInNamespace kube-system 5    

    if ($singlenode -eq $true) {
        WriteOut "Finished setting up a single-node cluster"
    }
    else {
        ShowCommandToJoinCluster $baseUrl    
    }

    return $Return    
}

function ConfigureFirewall() {
    [hashtable]$Return = @{} 

    WriteOut " --- installing firewalld ---"
    # https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-using-firewalld-on-centos-7
    sudo yum -y install firewalld
    sudo systemctl status firewalld
    WriteOut "--- removing iptables ---"
    sudo yum -y remove iptables-services
    WriteOut "enabling ports 6443 & 10250 for kubernetes and 80 & 443 for web apps in firewalld"
    # https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
    # kubernetes ports: https://kubernetes.io/docs/setup/independent/install-kubeadm/#check-required-ports
    # https://github.com/coreos/coreos-kubernetes/blob/master/Documentation/kubernetes-networking.md
    # https://github.com/coreos/tectonic-docs/blob/master/Documentation/install/rhel/installing-workers.md
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
    sudo firewall-cmd --add-port=30000-60000/udp --permanent # DNS
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
  
    sudo systemctl status firewalld  
  
    WriteOut "--- services enabled in firewall ---"
    sudo firewall-cmd --list-services
    WriteOut "--- ports enabled in firewall ---"
    sudo firewall-cmd --list-ports
  
    sudo firewall-cmd --list-all

    return $Return        
}
  
function SetupNewNode([ValidateNotNullOrEmpty()] $baseUrl) {
    [hashtable]$Return = @{} 

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
    sudo systemctl status ntpd

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
    sudo systemctl status docker

    Write-Status "--- Adding kubernetes repo ---"
    sudo yum-config-manager --add-repo ${baseUrl}/onprem/kubernetes.repo

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

    # WriteOut "--- setting up iptables for kubernetes ---"
    # # Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
    # cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
    # net.bridge.bridge-nf-call-ip6tables = 1
    # net.bridge.bridge-nf-call-iptables = 1
    # EOF
    # sudo sysctl --system

    Write-Status "--- finished setting up node ---"

    return $Return    
}
