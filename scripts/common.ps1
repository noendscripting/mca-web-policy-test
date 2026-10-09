# Helpers shared by deploy-oidc.ps1 and deploy-saml.ps1. Dot-source this file; do not run it directly.

function Assert-Az {
  param([string]$Message)
  if ($LASTEXITCODE) { throw $Message }
}

# Creates or updates the resources both web apps share: resource group, App Service plan,
# VNet, private Storage account, and containers. It never creates or changes a web app,
# so it is safe to run before either deployment and to repeat.
function Install-SharedInfrastructure {
  param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$Location,
    [string]$EnvironmentName,
    [string]$StorageAccountName
  )

  $subscription = az account show --query '{id:id,name:name}' --output json | ConvertFrom-Json
  Assert-Az 'Not signed in. Run "az login" first.'
  Write-Host "Subscription: $($subscription.name) ($($subscription.id))"

  az group create --name $ResourceGroup --location $Location --output none
  Assert-Az 'Creating the resource group failed.'

  if (-not $StorageAccountName) {
    $StorageAccountName = 'mca' + $subscription.id.Replace('-', '').Substring(0, 12)
  }

  $parameters = @("storageAccountName=$StorageAccountName")
  if ($EnvironmentName) { $parameters += "environmentName=$EnvironmentName" }

  Write-Host 'Provisioning shared Azure resources (plan, network, storage)...'
  $outputs = az deployment group create `
    --resource-group $ResourceGroup `
    --name 'mca-shared-infrastructure' `
    --template-file (Join-Path $PSScriptRoot '..\infra\main.bicep') `
    --parameters $parameters `
    --query properties.outputs --output json | ConvertFrom-Json
  Assert-Az 'Shared infrastructure deployment failed.'
  return $outputs
}

# Creates or updates one web app on the shared plan, network, and storage.
function Install-WebApp {
  param(
    [Parameter(Mandatory)][ValidateSet('oidc', 'saml')][string]$AuthProvider,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$WebAppName,
    [Parameter(Mandatory)]$Shared
  )

  Write-Host "Provisioning the $($AuthProvider.ToUpper()) web app '$WebAppName'..."
  $outputs = az deployment group create `
    --resource-group $ResourceGroup `
    --name "mca-web-$AuthProvider" `
    --template-file (Join-Path $PSScriptRoot '..\infra\web-app.bicep') `
    --parameters "name=$WebAppName" "authProvider=$AuthProvider" `
      "appServicePlanName=$($Shared.appServicePlanName.value)" `
      "virtualNetworkName=$($Shared.virtualNetworkName.value)" `
      "integrationSubnetName=$($Shared.integrationSubnetName.value)" `
      "storageAccountName=$($Shared.storageAccountName.value)" `
    --query properties.outputs --output json | ConvertFrom-Json
  Assert-Az "Deploying the $AuthProvider web app failed."
  return $outputs
}

function Get-AppSetting {
  param([string]$WebApp, [string]$ResourceGroup, [string]$Name)
  az webapp config appsettings list --name $WebApp --resource-group $ResourceGroup --query "[?name=='$Name'].value | [0]" --output tsv
}

# Settings go through a JSON file so special characters in secrets and URLs are never
# re-parsed by the shell. The file is removed even on failure.
function Set-AppSettings {
  param([string]$WebApp, [string]$ResourceGroup, [hashtable]$Settings)

  $file = Join-Path ([IO.Path]::GetTempPath()) "appsettings-$([guid]::NewGuid().ToString('N')).json"
  try {
    $Settings | ConvertTo-Json | Set-Content -Path $file -Encoding utf8
    az webapp config appsettings set --name $WebApp --resource-group $ResourceGroup --settings "@$file" --output none
    Assert-Az 'Setting app settings failed.'
  }
  finally {
    Remove-Item $file -ErrorAction SilentlyContinue
  }
}

function New-BaseSettings {
  param([string]$WebApp, [string]$ResourceGroup, [string]$AuthProvider, [string]$StorageAccountName, [string]$ContainerName)

  $secret = Get-AppSetting -WebApp $WebApp -ResourceGroup $ResourceGroup -Name 'SESSION_SECRET'
  if (-not $secret) { $secret = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') }

  return @{
    AUTH_PROVIDER                   = $AuthProvider
    NODE_ENV                        = 'production'
    WEBSITES_PORT                   = '3000'
    SCM_DO_BUILD_DURING_DEPLOYMENT  = 'true'
    SESSION_SECRET                  = $secret
    AZURE_STORAGE_ACCOUNT_NAME      = $StorageAccountName
    AZURE_STORAGE_CONTAINER_NAME    = $ContainerName
  }
}

function Publish-App {
  param([string]$WebApp, [string]$ResourceGroup)
  & (Join-Path $PSScriptRoot 'deploy.ps1') -WebAppName $WebApp -ResourceGroup $ResourceGroup
}

function Test-Deployment {
  param([string]$Url, [string]$AuthProvider, [bool]$RequireAuthEnabled = $true)

  Write-Host "Checking $Url/health (the first start can take a few minutes)..."
  $health = $null
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $health = Invoke-RestMethod "$Url/health" -TimeoutSec 20
      if ($health.authProvider -eq $AuthProvider) { break }
    }
    catch { $health = $null }
    Start-Sleep -Seconds 10
  }

  if (-not $health) { throw "The app did not respond at $Url/health. Run: az webapp log tail" }
  if ($health.authProvider -ne $AuthProvider) {
    throw "Expected authProvider '$AuthProvider' but the app reports '$($health.authProvider)'."
  }
  if ($RequireAuthEnabled -and -not $health.authEnabled) {
    throw "The app is running as $AuthProvider but sign-in is not enabled. Check the app settings and logs."
  }
  Write-Host "Health: storage=$($health.storage) authProvider=$($health.authProvider) authEnabled=$($health.authEnabled)"
}
