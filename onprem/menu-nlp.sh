#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/kubernetes/main.sh | bash
#
#
version="2018.04.10.01"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"

source <(curl -sSL "$GITHUB_URL/common/common.sh?p=$RANDOM")
# source ./common/common.sh

input=""
while [[ "$input" != "q" ]]; do

    echo "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    echo "------ Product Install -------"
    echo "25: Install NLP"
    echo "------ NLP -----"
    echo "41: Show status of NLP"
    echo "42: Test web sites"
    echo "43: Show NLP passwords"
    echo "44: Show detailed status of NLP"
    echo "45: Show NLP logs"
    echo "q: Quit"

    read -p "Please make a selection:" -e input  < /dev/tty 

    case "$input" in
    25)  InstallStack $GITHUB_URL "fabricnlp" "nlp"
        ;;
    41)  kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        ;;
    43)  Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword fabricnlp)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword fabricnlp)"
            Write-Host "SendGrid SMTP Relay key: $(ReadSecretPassword smtprelaypassword fabricnlp)"
        ;;
    44)  pods=$(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Describe Pod: $pod ================="
                kubectl describe pods $pod -n fabricnlp
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;
    45)  pods=$(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Logs for Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricnlp
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
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