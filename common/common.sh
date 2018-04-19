
versioncommon="2018.04.17.02"

echo "--- Including common.sh version $versioncommon ---"
function GetCommonVersion() {
    echo $versioncommon
}

function Write-Output()
{
    echo $1
}

function Write-Host()
{
    echo $1
}

function Write-Status(){
    echo "$1";
}

function InstallPrerequisites(){
    Write-Status "--- updating yum packages ---"
    #sudo yum update -y -q -e 0
    sudo yum update -y

    echo "---- RAM ----"
    declare -i freememInBytes=10
    freememInBytes=$(free|awk '/^Mem:/{print $2}')
    freememInMB=$(($freememInBytes/1024))
    echo "Free Memory: $freememInMB MB"
    free -h
    echo "--- disk space ---"
    df -h

    Write-Status "installing yum-utils and other packages"
    # yum-version: lock yum packages so they don't update automatically
    # yum-utils: for yum-config-manager
    # net-tools: for DNS tools
    # nmap: nmap command for listing open ports
    # curl: for downloading
    # lsof: show open files
    # ntp: Network Time Protocol
    # nano: simple editor
    # bind-utils: for dig, host

    sudo yum -y install yum-versionlock yum-utils net-tools nmap curl lsof ntp nano bind-utils 

    Write-Status "removing unneeded packages"
    # https://www.tecmint.com/remove-unwanted-services-in-centos-7/
    sudo yum -y remove postfix chrony

    Write-Status "turning off swap"
    # https://blog.alexellis.io/kubernetes-in-10-minutes/
    sudo swapoff -a
    echo "removing swap from /etc/fstab"
    grep -v "swap" /etc/fstab | sudo tee /etc/fstab
    echo "--- current swap files ---"
    sudo cat /proc/swaps
    
    # Register the Microsoft RedHat repository
    echo "--- adding microsoft repo for powershell ---"
    sudo yum-config-manager --add-repo https://packages.microsoft.com/config/rhel/7/prod.repo

    # curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo

    # Install PowerShell
    echo "--- installing powershell ---"
    sudo yum install -y powershell
    # sudo yum install -y powershell-6.0.2-1.rhel.7
    # sudo yum versionlock powershell    
}
function createShortcutFordos(){
    local baseUrl=$1

    mkdir -p $HOME/bin
    installscript="$HOME/bin/dos"
    if [[ ! -f "$installscript" ]]; then
        echo "#!/bin/bash" > $installscript
        echo curl -o "${HOME}/master.ps1" -sSL "${GITHUB_URL}/menus/master.ps1?p="'$RANDOM' >> $installscript
        echo pwsh -f "${HOME}/master.ps1" >> $installscript
        chmod +x $installscript
        echo "NOTE: Next time just type 'dos' to bring up this menu"

        # from http://web.archive.org/web/20120621035133/http://www.ibb.net/~anne/keyboard/keyboard.html
        # curl -o ~/.inputrc "$GITHUB_URL/kubernetes/inputrc"
    fi    
}

echo "--- Finished including common.sh version $versioncommon ---"
