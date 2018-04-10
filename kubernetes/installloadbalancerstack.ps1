param([int]$ssl, [string]$ingressInternal, [string]$ingressExternal, [string]$customerid, [string]$publicIp)
# the above MUST be the first line
Write-Output "Received parameters:"
Write-Output "ssl:$ssl"
Write-Output "ingressInternal:$ingressInternal"
Write-Output "ingressExternal:$ingressExternal"
Write-Output "customerid:$customerid"
Write-Output "publicIp:$publicIp"
Write-Output "----"
Write-Output "Version 2018.04.10.01"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/setup-loadbalancer.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Write-Output "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

$ckscript=$(Invoke-WebRequest -useb ${GITHUB_URL}/common/common-kube.ps1?f=$randomstring)
Invoke-Expression $($ckscript);
# Get-Content ./common/common-kube.ps1 -Raw | Invoke-Expression;

$cmscript=$(Invoke-WebRequest -useb $GITHUB_URL/common/common.ps1?f=$randomstring)
Invoke-Expression $($cmscript);
# Get-Content ./common/common.ps1 -Raw | Invoke-Expression;

LoadLoadBalancerStack -baseUrl $GITHUB_URL -ssl $ssl -ingressInternal $ingressInternal -ingressExternal $ingressExternal -customerid $customerid -publicIp $publicIp *>&1 | Tee-Object -FilePath "loadbalancer.log"