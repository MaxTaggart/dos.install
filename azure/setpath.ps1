Write-Host "--- setpath Version 2018.04.02.02 ----"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/setpath.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1 | Invoke-Expression;
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1 | Invoke-Expression;
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

# where to store the SSH keys on local machine
$AKS_LOCAL_FOLDER = "c:\kubernetes"
AddFolderToPathEnvironmentVariable -folder $AKS_LOCAL_FOLDER

$AKS_LOCAL_FOLDER = "c:\kubernetes\azcli\CLI2\wbin"
AddFolderToPathEnvironmentVariable -folder $AKS_LOCAL_FOLDER

Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

