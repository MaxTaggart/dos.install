#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/onprem/setupnode.sh | bash
#
#

version="2018.04.11.03"
echo "---- setupnode version $version ----"

dockerversion="17.03.2.ce-1"

u="$(whoami)"
echo "User name: $u"

echo "updating yum packages"
sudo yum update -y

echo "---- RAM ----"
free -h
echo "--- disk space ---"
df -h

echo "installing yum-utils and other packages"
# yum-version: lock yum packages so they don't update automatically
# yum-utils: for yum-config-manager
# net-tools: for DNS tools
# nmap: nmap command for listing open ports
# curl: for downloading
# lsof: show open files
# ntp: Network Time Protocol
# nano: simple editor
# bind-utils: for dig
# iptables-services: for iptables firewall
sudo yum -y install yum-versionlock yum-utils net-tools nmap curl lsof ntp nano bind-utils

echo "removing unneeded packages"
# https://www.tecmint.com/remove-unwanted-services-in-centos-7/
sudo yum -y remove postfix chrony iptables-services

echo "turning off swap"
# https://blog.alexellis.io/kubernetes-in-10-minutes/
sudo swapoff -a
# comment out swap file in /etc/fstab
echo "--- current swap files ---"
sudo cat /proc/swaps

# echo "switching from firewalld to iptables"
# # https://www.digitalocean.com/community/tutorials/how-to-migrate-from-firewalld-to-iptables-on-centos-7
# sudo systemctl stop firewalld && sudo systemctl start iptables; sudo systemctl start ip6tables
# # sudo firewall-cmd --state
# sudo systemctl disable firewalld
# sudo systemctl enable iptables
# sudo systemctl enable ip6tables

# echo "setting up iptables rules"
# # https://www.digitalocean.com/community/tutorials/iptables-essentials-common-firewall-rules-and-commands
# echo "allowing loopback connections"
# sudo iptables -A INPUT -i lo -j ACCEPT
# sudo iptables -A OUTPUT -o lo -j ACCEPT
# echo "allowing established and related incoming connections"
# sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# echo "allowing established outgoing connections"
# sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
# echo "allowing docker containers to access the external network"
# sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
# sudo iptables -A FORWARD -i docker0 -o eth0 -j ACCEPT
# echo "allow all incoming ssh"
# sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# sudo iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
# # reject an IP address
# # sudo iptables -A INPUT -s 15.15.15.51 -j REJECT
# echo "allow incoming HTTP"
# sudo iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# sudo iptables -A OUTPUT -p tcp --sport 80 -m conntrack --ctstate ESTABLISHED -j ACCEPT
# echo "allow incoming HTTPS"
# sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# sudo iptables -A OUTPUT -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT
# #echo "block outgoing SMTP Mail"
# #sudo iptables -A OUTPUT -p tcp --dport 25 -j REJECT
# echo "---- current iptables rules ---"
# sudo iptables -t nat -L

echo "enabling ports 6443 & 10250 for kubernetes and 80 & 443 for web apps in firewalld"
# https://www.tecmint.com/things-to-do-after-minimal-rhel-centos-7-installation/3/
# kubernetes ports: https://kubernetes.io/docs/setup/independent/install-kubeadm/#check-required-ports

sudo firewall-cmd --add-port=6443/tcp --permanent # kubernetes API server
sudo firewall-cmd --add-port=10250/tcp --permanent # Kubelet API
sudo firewall-cmd --add-port=10255/tcp --permanent # Read-only Kubelet API
sudo firewall-cmd --add-port=80/tcp --permanent # HTTP
sudo firewall-cmd --add-port=443/tcp --permanent # HTTPS
sudo firewall-cmd --add-service=ntp --permanent # NTP server
sudo firewall-cmd --reload

echo "-- starting NTP deamon ---"
# https://www.tecmint.com/install-ntp-server-in-centos/
sudo systemctl start ntpd
sudo systemctl enable ntpd
sudo systemctl status ntpd

echo "--- stopping docker and kubectl ---"
servicestatus=$(systemctl show -p SubState kubelet)
if [[ $servicestatus = *"running"* ]]; then
  echo "stopping kubelet"
  sudo systemctl stop kubelet
fi

# remove older versions
# sudo systemctl stop docker 2>/dev/null
echo "--- Removing previous versions of kubernetes and docker --"
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

echo "--- Adding docker repo --"
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

sudo yum -y repolist

echo "-- docker versions available in repo --"
sudo yum -y --showduplicates list docker-ce

echo "--- Installing docker via yum --"
# need to pass --setpot=obsoletes=0 due to this bug: https://github.com/docker/for-linux/issues/20#issuecomment-312122325
sudo yum install -y --setopt=obsoletes=0 docker-ce-${dockerversion}.el7.centos docker-ce-selinux-${dockerversion}.el7.centos
echo "--- Locking version of docker so it does not get updated via yum update --"
sudo yum versionlock docker-ce
sudo yum versionlock docker-ce-selinux

# https://kubernetes.io/docs/setup/independent/install-kubeadm/
# log rotation for docker: https://docs.docker.com/config/daemon/
# https://docs.docker.com/config/containers/logging/json-file/
echo "--- Configuring docker to use systemd and set logs to max size of 10MB and 5 days --"
sudo mkdir -p /etc/docker
cat << EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  }  
}
EOF

echo "--- Starting docker service --"
sudo systemctl enable docker && sudo systemctl start docker

if [ $u != "root" ]; then
    echo "--- Giving permission to $u to interact with docker ---"
    sudo usermod -aG docker $u
    # reload permissions without requiring a logout
    # from https://superuser.com/questions/272061/reload-a-linux-users-group-assignments-without-logging-out
    # https://man.cx/newgrp(1)
    echo "--- Reloading permissions via newgrp ---"
    newgrp docker
fi

echo "--- Adding kubernetes repo ---"

cat << EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# install kubeadm
# https://saurabh-deochake.github.io/posts/2017/07/post-1/
echo "disabling selinux"
sudo setenforce 0

echo "--- Removing previous versions of kubernetes ---"
sudo yum remove -y kubelet kubeadm kubectl kubernetes-cni

echo "--- checking to see if port 10250 is still busy ---"
sudo lsof -i -P -n | grep LISTEN

echo "--- kubernetes versions available in repo ---"
sudo yum -y --showduplicates list kubelet kubeadm kubectl kubernetes-cni

echo "--- installing kubernetes ---"
sudo yum install -y kubelet-1.9.3-0 kubeadm-1.9.3-0 kubectl-1.9.6-0 kubernetes-cni-0.6.0-0
echo "--- locking versions of kubernetes so they don't get updated by yum update ---"
sudo yum versionlock kubelet
sudo yum versionlock kubeadm
sudo yum versionlock kubectl
sudo yum versionlock kubernetes-cni

echo "--- starting kubernetes service ---"
sudo systemctl enable kubelet && sudo systemctl start kubelet

echo "--- setting up iptables for kubernetes ---"
# Some users on RHEL/CentOS 7 have reported issues with traffic being routed incorrectly due to iptables being bypassed
cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

echo "---- finish setupnode version $version ----"