param([String]$namespace, [String]$appfolder, [int]$isAzure)
# the above MUST be the first line
Write-Host "Received parameters:"
Write-Host "namespace:$namespace"
Write-Host "appfolder:$appfolder"
Write-Host "isAzure:$isAzure"
Write-Host "----"
Write-Host "Version 2018.03.28.02"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1 | Invoke-Expression;
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1 | Invoke-Expression;
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

InstallStack -namespace $namespace -baseUrl $GITHUB_URL -appfolder "$appfolder" -isAzure $isAzure *>&1 | Tee-Object -FilePath "${namespace}.log"
