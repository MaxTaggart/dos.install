param([int]$ssl, [string]$ingressInternal, [string]$ingressExternal, [string]$customerid, [string]$publicIp)
# the above MUST be the first line
Write-Host "Received parameters:"
Write-Host "ssl:$ssl"
Write-Host "ingressInternal:$ingressInternal"
Write-Host "ingressExternal:$ingressExternal"
Write-Host "customerid:$customerid"
Write-Host "publicIp:$publicIp"
Write-Host "----"
Write-Host "Version 2018.03.28.01"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/setup-loadbalancer.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Write-Host "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

LoadLoadBalancerStack -baseUrl $GITHUB_URL -ssl $ssl -ingressInternal $ingressInternal -ingressExternal $ingressExternal -customerid $customerid -publicIp $publicIp *>&1 | Tee-Object -FilePath "loadbalancer.log"