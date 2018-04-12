#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/setupmaster.txt | bash
#
#

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
source <(curl -sSL "$GITHUB_URL/common/common.sh")

version="2018.04.12.01"
echo "---- setupmaster version $version ----"

kubernetesversion="1.9.6"

u="$(whoami)"
echo "User name: $u"

# for calico network plugin
# echo "--- running kubeadm init for calico ---"
# sudo kubeadm init --kubernetes-version=v1.9.6 --pod-network-cidr=192.168.0.0/16

# CLUSTER_DNS_CORE_DNS="true"

# echo "--- running kubeadm init for flannel ---"
# for flannel network plugin
sudo kubeadm init --kubernetes-version=v${kubernetesversion} --pod-network-cidr=192.168.0.0/16 --feature-gates CoreDNS=true

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
kubectl apply -f ${GITHUB_URL}/kubernetes/cni/flannel.yaml

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

# Register the Microsoft RedHat repository
echo "--- adding microsoft repo for powershell ---"
sudo yum-config-manager \
   --add-repo \
   https://packages.microsoft.com/config/rhel/7/prod.repo

# curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo

# Install PowerShell
echo "--- installing powershell ---"
sudo yum install -y powershell

# Start PowerShell
# pwsh

echo "---- end setupmaster version $version ----"
