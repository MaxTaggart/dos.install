#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/setup-loadbalancer.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")
# source ./common/common.sh

version="2018.03.28.01"

echo "---- setup-loadbalancer.sh version $version ------"

# enable running pods on master
# kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule
echo "--- deleting existing resources with label traefik ---"
kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

echo "--- deleting existing service account for traefik ---"
kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

AKS_IP_WHITELIST=""
publicip=""

AskForSecretValue "customerid" "Customer ID "
customerid=$(ReadSecret "customerid")

AskForSecretValue "dnshostname" "DNS name used to connect to the master VM "
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

yamlfile="loadbalancer/configmaps/config.ssl.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="loadbalancer/roles/ingress-roles.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="loadbalancer/pods/ingress-onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="loadbalancer/services/cluster/dashboard-onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="loadbalancer/services/external/loadbalancer.onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

loadbalancer="traefik-ingress-service-public"
loadBalancerIP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
echo "My WAN/Public IP address: ${loadBalancerIP}"
    
echo "To test out the load balancer, open Git Bash and run:"
echo "curl -L --verbose --header 'Host: $dnsrecordname' 'http://$loadBalancerIP/' -k"        

echo "---- end of setup-loadbalancer.sh version $version ------"