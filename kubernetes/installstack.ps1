param([String]$namespace, [String]$appfolder, [int]$isAzure)
# the above MUST be the first line
Write-Host "Received parameters:"
Write-Host "namespace:$namespace"
Write-Host "appfolder:$appfolder"
Write-Host "isAzure:$isAzure"
Write-Host "----"
Write-Host "Version 2018.04.02.01"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "."

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

$ckscript=$(Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring)
Invoke-Expression $($ckscript);
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

$cmscript=$(Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring)
Invoke-Expression $($cmscript);
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

InstallStack -namespace $namespace -baseUrl $GITHUB_URL -appfolder "$appfolder" -isAzure $isAzure *>&1 | Tee-Object -FilePath "${namespace}.log"
