param([String]$namespace, [String]$appfolder, [int]$isAzure)
# the above MUST be the first line
Write-Output "installstack.ps1 version 2018.04.10.02"
Write-Output "Received parameters:"
Write-Output "namespace:$namespace"
Write-Output "appfolder:$appfolder"
Write-Output "isAzure:$isAzure"
Write-Output "----"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "."

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

# don't show progress display since it causes PS to display from top
# https://stackoverflow.com/questions/18770723/hide-progress-of-invoke-webrequest
# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-6&viewFallbackFrom=powershell-Microsoft.PowerShell.Core
$progressPreference = "silentlyContinue"

$ckscript=$(Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring)
Invoke-Expression $($ckscript);
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

$cmscript=$(Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring)
Invoke-Expression $($cmscript);
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

InstallStack -namespace $namespace -baseUrl $GITHUB_URL -appfolder "$appfolder" -isAzure $isAzure *>&1 | Tee-Object -FilePath "${namespace}.log"
