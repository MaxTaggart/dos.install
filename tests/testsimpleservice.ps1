$GITHUB_URL = "C:\Catalyst\git\dos.install"

Get-Content $GITHUB_URL/common/common-kube.ps1 -Raw | Invoke-Expression;

$GITHUB_URL = "C:\Catalyst\git\dos.install"
$namespace="test"
$appfolder="templates"

$configpath = "$GITHUB_URL/${appfolder}/index2.json"
$config = $(Get-Content $configpath -Raw | ConvertFrom-Json)
$services = $($config.resources.simpleservices)

$service= $($services[0])

DeploySimpleService -namespace $namespace -baseUrl $GITHUB_URL -appfolder "$appfolder" -customerid hcut -service $service

