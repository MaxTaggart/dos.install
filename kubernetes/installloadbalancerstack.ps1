param([int]$ssl, [string]$ingressInternal, [string]$ingressExternal, [string]$customerid, [string]$publicIp)
# the above MUST be the first line
Write-Output "installloadbalancerstack.ps1 version 2018.04.10.01"
Write-Output "Received parameters:"
Write-Output "ssl:$ssl"
Write-Output "ingressInternal:$ingressInternal"
Write-Output "ingressExternal:$ingressExternal"
Write-Output "customerid:$customerid"
Write-Output "publicIp:$publicIp"
Write-Output "----"


#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/setup-loadbalancer.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Write-Output "GITHUB_URL: $GITHUB_URL"

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

LoadLoadBalancerStack -baseUrl $GITHUB_URL -ssl $ssl -ingressInternal $ingressInternal -ingressExternal $ingressExternal -customerid $customerid -publicIp $publicIp *>&1 | Tee-Object -FilePath "loadbalancer.log"