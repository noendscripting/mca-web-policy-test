<#
.SYNOPSIS
  Deploys the OIDC (Microsoft Entra ID OpenID Connect) web app. Fully automated.
.DESCRIPTION
  Creates the shared resources if they are missing (resource group, App Service plan, VNet,
  Storage), then deploys only the OIDC web app. The SAML web app is not created or changed;
  deploy it separately with deploy-saml.ps1, using the same -ResourceGroup and -EnvironmentName.
.EXAMPLE
  .\scripts\deploy-oidc.ps1 -Location eastus
#>
param(
  [Parameter(Mandatory)][string]$Location,
  [string]$ResourceGroup = 'rg-mca-web-policy-test',
  [string]$EnvironmentName = 'mcawebpolicy',
  [string]$StorageAccountName,
  [string]$AppDisplayName = 'mca-web-policy-oidc'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$shared = Install-SharedInfrastructure -ResourceGroup $ResourceGroup -Location $Location `
  -EnvironmentName $EnvironmentName -StorageAccountName $StorageAccountName
$app = Install-WebApp -AuthProvider oidc -ResourceGroup $ResourceGroup -WebAppName "$EnvironmentName-oidc-web" -Shared $shared
$webApp = $app.name.value
$url = $app.url.value
$redirectUri = "$url/auth/callback"
$tenantId = az account show --query tenantId --output tsv

# Entra app registration (reused if it already exists).
Write-Host "Configuring Entra app registration '$AppDisplayName'..."
$clientId = az ad app list --display-name $AppDisplayName --query '[0].appId' --output tsv
if ($clientId) {
  az ad app update --id $clientId --web-redirect-uris $redirectUri --enable-id-token-issuance true --output none
  Assert-Az 'Updating the app registration failed.'
}
else {
  $clientId = az ad app create --display-name $AppDisplayName --sign-in-audience AzureADMyOrg `
    --web-redirect-uris $redirectUri --enable-id-token-issuance true --query appId --output tsv
  Assert-Az 'Creating the app registration failed.'
}

# A service principal is required so MDCA can evaluate the app.
if (-not (az ad sp list --filter "appId eq '$clientId'" --query '[0].id' --output tsv)) {
  az ad sp create --id $clientId --output none
  Assert-Az 'Creating the service principal failed.'
}

# Expose api://<client-id> with the access_as_user scope that sign-in requests.
$hasScope = az ad app show --id $clientId --query "api.oauth2PermissionScopes[?value=='access_as_user'] | length(@)" --output tsv
if ($hasScope -eq '0') {
  $body = @{
    identifierUris = @("api://$clientId")
    api            = @{
      oauth2PermissionScopes = @(@{
          id                      = [guid]::NewGuid().ToString()
          value                   = 'access_as_user'
          type                    = 'User'
          isEnabled               = $true
          adminConsentDisplayName = 'Access the MCA web policy test app'
          adminConsentDescription = 'Allows the app to sign the user in and access the app on their behalf.'
          userConsentDisplayName  = 'Access the MCA web policy test app'
          userConsentDescription  = 'Allows the app to sign you in and access the app on your behalf.'
        })
    }
  } | ConvertTo-Json -Depth 6
  $bodyFile = Join-Path ([IO.Path]::GetTempPath()) "oidc-api-$([guid]::NewGuid().ToString('N')).json"
  try {
    Set-Content -Path $bodyFile -Value $body -Encoding utf8
    az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications(appId='$clientId')" `
      --headers 'Content-Type=application/json' --body "@$bodyFile" --output none
    Assert-Az 'Exposing the access_as_user scope failed.'
  }
  finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
  }
}

$clientSecret = az ad app credential reset --id $clientId --append --years 1 --query password --output tsv
Assert-Az 'Creating the client secret failed.'

$settings = New-BaseSettings -WebApp $webApp -ResourceGroup $ResourceGroup -AuthProvider oidc `
  -StorageAccountName $shared.storageAccountName.value -ContainerName $shared.storageContainerName.value
$settings.AAD_TENANT_ID = $tenantId
$settings.AAD_CLIENT_ID = $clientId
$settings.AAD_CLIENT_SECRET = $clientSecret
$settings.OIDC_REDIRECT_URI = $redirectUri
Set-AppSettings -WebApp $webApp -ResourceGroup $ResourceGroup -Settings $settings

Publish-App -WebApp $webApp -ResourceGroup $ResourceGroup
Test-Deployment -Url $url -AuthProvider oidc

Write-Host ''
Write-Host "OIDC app is ready: $url"
Write-Host "Client ID: $clientId"
