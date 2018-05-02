param([bool]$prerelease)    
Write-Host "prerelease flag: $prerelease"

if($prerelease){
    $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/master"
}
else
{
    $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/dos.install/release"
}
Write-Host "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$result += $set | Get-Random
Invoke-WebRequest -useb ${GITHUB_URL}/azure/main.ps1?f=$result | Invoke-Expression;
