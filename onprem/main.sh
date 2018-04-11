#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/main.sh | bash
#   curl https://bit.ly/2GOPcyX | bash
#
version="2018.04.10.05"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

if [ ! -x "$(command -v yum)" ]; then
    echo "yum command is not available"
    exit
fi

echo "CentOS version: $(cat /etc/redhat-release | grep -o '[0-9]\.[0-9]')"
echo "$(cat /etc/redhat-release)"

declare -i freememInBytes=10
freememInBytes=$(free|awk '/^Mem:/{print $2}')
freememInMB=$(($freememInBytes/1024))
echo "Free Memory: $freememInMB MB"

source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")
# source ./common/common.sh

# this sets the keyboard so it handles backspace properly
# http://www.peachpit.com/articles/article.aspx?p=659655&seqNum=13
echo "running stty sane to fix terminal keyboard mappings"
stty sane < /dev/tty

# echo "setting TERM to xterm"
# export TERM=xterm

mkdir -p $HOME/bin
installscript="$HOME/bin/dos"
if [[ ! -f "$installscript" ]]; then
    echo "#!/bin/bash" > $installscript
    echo "curl -sSL $GITHUB_URL/"'onprem/main.sh?p=$RANDOM | bash' >> $installscript
    chmod +x $installscript
    echo "NOTE: Next time just type 'dos' to bring up this menu"

    # from http://web.archive.org/web/20120621035133/http://www.ibb.net/~anne/keyboard/keyboard.html
    # curl -o ~/.inputrc "$GITHUB_URL/kubernetes/inputrc"
fi

input=""
while [[ "$input" != "q" ]]; do

    echo "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    echo "------ Setup Master Node -------"
    echo "1: Add this VM as Master"
    echo "------ Setup Worker Node -------"
    echo "12: Add this VM as Worker"
    echo "--- Master Node tasks --------"
    echo "2: Show all nodes"
    echo "3: Show command to join another node to this cluster"
    echo "4: Mount shared folder"
    echo "5: Mount Azure Storage as shared folder"
    echo "6: Setup Load Balancer"
    echo "7: Setup Kubernetes Dashboard"
    echo "8: Uninstall Docker & Kubernetes"
    echo "9: Create a single node cluster"
    echo "10: Fix Centos under Hyper-V"
    echo "------ Worker Node Tasks-------"
    echo "12: Add this VM as Worker"
    echo "13: Join this VM to an existing cluster"
    echo "14: Mount shared folder"
    echo "15: Mount Azure Storage as shared folder"
    echo "16: Uninstall Docker & Kubernetes"
    echo "----- Troubleshooting ----"
    echo "31: Show status of cluster"
    # echo "32: Launch Kubernetes Admin Dashboard"
    # echo "33: View status of DNS pods"
    # echo "34: Apply updates and restart all VMs"
    echo "35: Show load balancer logs"
    echo "36: Show open ports"
    echo "37: Test DNS"
    echo "38: Show contents of shared folder"
    echo "39: Show dashboard url"
    echo "-----------"
    echo "51: Load Fabric Realtime Menu"
    echo "52: Load NLP Menu"
    echo "q: Quit"

    read -p "Please make a selection:" -e input  < /dev/tty 

    case "$input" in
    1)  SetupMaster $GITHUB_URL false
        ;;
    2)  echo "Current cluster: $(kubectl config current-context)"
        kubectl version --short
        kubectl get "nodes"
        ;;
    3)  ShowCommandToJoinCluster $GITHUB_URL
        ;;
    4)  mountSMB true
        ;;
    5)  mountAzureFile true
        ;;
    6)  # cannot use tee here because it calls a ps1 file
        curl -sSL $GITHUB_URL/onprem/setup-loadbalancer.sh?p=$RANDOM | bash
        ;;
    7)  InstallStack $GITHUB_URL "kube-system" "dashboard"
        ;;
    8)  if [ -x "$(command -v kubeadm)" ]; then
            sudo kubeadm reset
        fi    
        sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
        if [ -x "$(command -v docker)" ]; then
            sudo docker system prune -f
            # sudo docker volume rm etcd
        fi
        sudo rm -rf /var/etcd/backups/*
        sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
        sudo yum -y remove docker docker-common docker-selinux docker-engine    
        echo "Please restart this computer"
        ;;
    9)  SetupMaster $GITHUB_URL true
        ;;
    10) # from https://www.altaro.com/hyper-v/centos-linux-hyper-v/
        echo "installing hyperv-daemons package"
    	sudo yum install -y hyperv-daemons
        echo "turning off disk optimization in centos since Hyper-V already does disk optimization"
        echo "noop" | sudo tee /sys/block/sda/queue/scheduler
        echo "You can connect to this machine via SSH: ssh $(whoami)@$(hostname -i)"
        grep -v "$(hostname)" /etc/hosts | sudo tee /etc/hosts > /dev/null
        echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts > /dev/null
        ;;
    12)  curl -sSL $GITHUB_URL/onprem/setupnode.sh?p=$RANDOM | bash 2>&1 | tee setupnode.log
        mountSharedFolder false
        JoinNodeToCluster
        ;;
    13) JoinNodeToCluster
        ;;
    14)  mountSMB false
        ;;
    15)  mountAzureFile false
        ;;
    16) sudo kubeadm reset 2>/dev/null
        sudo docker system prune -f 2>/dev/null
        sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
        sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
        sudo yum -y remove docker docker-common docker-selinux docker-engine    
        echo "Please restart this computer"
        ;;
    31)  echo "Current cluster: $(kubectl config current-context)"
        kubectl version --short
        kubectl get "deployments,pods,services,nodes,ingress,secrets" --namespace=kube-system -o wide
        ;;
    35) kubectl logs --namespace=kube-system -l k8s-app=traefik-ingress-lb-onprem --tail=100
    ;;
    36) # https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
        echo "---- open ports ----" 
        sudo nmap 127.0.0.1
        echo "--- IP services ---"
        sudo firewall-cmd --list-services
    ;;
    37)  # from https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#debugging-dns-resolution
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

        kubectl create -f $GITHUB_URL/kubernetes/test/busybox.yaml
        while [[ "$(kubectl get pods busybox -n default -o jsonpath='{.status.phase}')" != "Running" ]]; do
            echo "."
            sleep 5
        done
        kubectl exec busybox nslookup kubernetes.default
        kubectl exec busybox cat /etc/resolv.conf
        kubectl delete -f $GITHUB_URL/kubernetes/test/busybox.yaml
        ;;
    38)  ls -al /mnt/data
        ;;
    39)  dnshostname=$(ReadSecret "dnshostname")
        echo "You can access the kubernetes dashboard at: https://${dnshostname}/api/ "
        secretname=$(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
        token=$(ReadSecretValue "$secretname" "token" "kube-system")
        echo "----------- Bearer Token ---------------"
        echo $token
        echo "-------- End of Bearer Token -------------"
        ;;
    51) curl -sSL $GITHUB_URL/onprem/menu-realtime.sh?p=$RANDOM | bash
        ;;
    52) curl -sSL $GITHUB_URL/onprem/menu-nlp.sh?p=$RANDOM | bash
        ;;
    q) echo  "Exiting" 
    ;;
    *) echo "Menu item $1 is not known"
    ;;
    esac

echo ""
if [[ "$input" -eq "q" ]]; then
    exit
fi
read -p "[Press Enter to Continue]" < /dev/tty 
clear
done