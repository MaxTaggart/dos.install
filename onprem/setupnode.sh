#!/bin/sh
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/setupnode.txt | bash
#
#

version="2018.03.27.01"
echo "---- setupnode version $version ----"

u="$(whoami)"
echo "User name: $u"

sudo yum -y install yum-versionlock

sudo yum update -y

# remove older versions
# sudo systemctl stop docker 2>/dev/null
sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni
sudo yum -y remove docker-engine.x86_64 docker-ce docker-engine-selinux.noarch docker-cimprov.x86_64 docker-engine
sudo yum -y remove docker docker-common docker-selinux docker-engine
sudo rm -rf /var/lib/docker

sudo yum-config-manager \
    --add-repo \
    https://docs.docker.com/v1.13/engine/installation/linux/repo_files/centos/docker.repo

sudo yum repolist

echo "docker versions available in repo"
sudo yum --showduplicates list docker-engine

sudo yum install -y docker-engine-selinux-17.03.1.ce-1.el7.centos.noarch docker-engine-17.03.1.ce-1.el7.centos
sudo yum versionlock docker-engine

# https://kubernetes.io/docs/setup/independent/install-kubeadm/
# log rotation for docker: https://docs.docker.com/config/daemon/
# https://docs.docker.com/config/containers/logging/json-file/
sudo mkdir -p /etc/docker
cat << EOF | sudo tee -a /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }  
}
EOF

sudo systemctl enable docker && sudo systemctl start docker

if [ $u != "root" ]; then
    echo "giving permission to $u"
    sudo usermod -aG docker $u
    # reload permissions without requiring a logout
    # from https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
    # https://man.cx/newgrp(1)
    newgrp docker
fi

cat << EOF | sudo tee -a /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF


# install kubeadm
# https://saurabh-deochake.github.io/posts/2017/07/post-1/
sudo setenforce 0
# sudo systemctl stop kubelet 2>/dev/null
sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni

echo "checking to see if port 10250 is still busy"
sudo lsof -i -P -n | grep LISTEN

echo "kubernetes versions available in repo"
sudo yum --showduplicates list kubelet kubeadm kubectl kubernetes-cni

sudo yum install -y kubelet-1.9.3-0 kubeadm-1.9.3-0 kubectl-1.9.6-0 kubernetes-cni-0.6.0-0
sudo yum versionlock kubelet
sudo yum versionlock kubeadm
sudo yum versionlock kubectl
sudo yum versionlock kubernetes-cni

sudo systemctl enable kubelet && sudo systemctl start kubelet

# Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
cat << EOF | sudo tee -a /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

echo "---- finish setupnode version $version ----"