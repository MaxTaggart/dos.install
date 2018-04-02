$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$result += $set | Get-Random
curl -useb https://raw.githubusercontent.com/HealthCatalyst/dos.install/master/azure/main.ps1?f=$result | iex;
