<powershell>
$rootdir = (Resolve-Path .\).Path
Write-Output "current directory is  $rootdir."

# --------------------------------------------------------------------
# Define the variables.
# --------------------------------------------------------------------
$AWS_REGION = "${s3_bucket_region}"                     # Update me, if required
$AWS_S3_BUCKET_NAME = "${s3_bucket_name}"               # Update me, if required
$AWS_S3_ARTIFACT_NAME = "${s3_artifact_name}"           # Update me, if required


$InetPubLog = "C:\Inetpub\Logs"
$InetPubWWWRoot = "C:\Inetpub\WWWRoot"

New-Item -Path 'C:\' -Name 'WindowsAWS' -ItemType directory

# --------------------------------------------------------------------
# Loading Feature Installation Modules
# --------------------------------------------------------------------
$Command = "icacls ..\ /grant ""Network Service"":(OI)(CI)W"
cmd.exe /c $Command
Write-Output "Granted network service access ..."

#Write-Output "Runbook started from webhook $WebhookName by $From."

# --------------------------------------------------------------------
# Loading IIS Modules
# --------------------------------------------------------------------
Import-Module ServerManager 

# --------------------------------------------------------------------
# Installing IIS
# --------------------------------------------------------------------
$features = @(
   "Web-WebServer",
   "Web-Static-Content",
   "Web-Http-Errors",
   "Web-Http-Redirect",
   "Web-Stat-Compression",
   "Web-Filtering",
   "Web-Asp-Net45",
   "Web-Net-Ext45",
   "Web-ISAPI-Ext",
   "Web-ISAPI-Filter",
   "Web-Mgmt-Console",
   "Web-Mgmt-Service",
   "Web-Mgmt-Tools",
   "NET-Framework-45-ASPNET"
)
Add-WindowsFeature $features -Verbose

Write-Output "Added all the Windows Features ..."
## --------------------------------------------------------------------
## Loading IIS and AWS Powershell Modules
## --------------------------------------------------------------------
Import-Module WebAdministration
Import-Module AWSPowerShell

## --------------------------------------------------------------------
## Setting directory access
## --------------------------------------------------------------------
$Command = "icacls $InetPubWWWRoot /grant BUILTIN\IIS_IUSRS:(OI)(CI)(RX) BUILTIN\Users:(OI)(CI)(RX)"
cmd.exe /c $Command
$Command = "icacls $InetPubLog /grant ""NT SERVICE\TrustedInstaller"":(OI)(CI)(F)"
cmd.exe /c $Command

Write-Output "Set directory access ..."

## --------------------------------------------------------------------
## Resetting IIS
## --------------------------------------------------------------------
$Command = "IISRESET"
Invoke-Expression -Command $Command

Write-Output "IIS Reset completed ..."
$source = "https://download.microsoft.com/download/0/1/D/01DC28EA-638C-4A22-A57B-4CEF97755C6C/WebDeploy_amd64_en-US.msi"
$dest = "C:\WindowsAWS\WebDeploy_amd64_en-US.msi"
Try
{
	Invoke-WebRequest $source -OutFile $dest
}
Catch
{
    Write-Output "Error downloading Web Deploy exe ..." | Write-Output
}
Write-Output "Web Deploy exe downloaded ..."

Set-Location "C:\WindowsAWS"

Try
{
    Start-Process msiexec -ArgumentList "/package WebDeploy_amd64_en-US.msi /qn /norestart ADDLOCAL=ALL  LicenseAccepted='0'" -Wait
}
Catch
{
    Write-Output "Error installing Webdeloy exe ..." | Write-Output
}

Write-Output "Web Deploy exe installed ..."

$MSDeployPath = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy" | Select-Object -Last 1).GetValue("InstallPath")

Write-Output "Web deploy is installed here ...$MSDeployPath"

Write-Output "Deploying the Web App package..."

Read-S3Object -BucketName $AWS_S3_BUCKET_NAME -Region $AWS_REGION -key $AWS_S3_ARTIFACT_NAME -File C:\\WindowsAWS\\test-web-application.zip

Try
{

$msdeployArguments = '-verb:sync',

       '-source:package="C:\WindowsAWS\test-web-application.zip"',

       '-dest:auto,ComputerName="localhost"',

       '-allowUntrusted'


& $MSDeployPath\msdeploy.exe $msdeployArguments
}
Catch
{
    Write-Output "Error deploying the web package" | Write-Output
}

Write-Output "The Web package has been deployed"
</powershell>