<#
.SYNOPSIS
  Deploys the SAML (Microsoft Entra ID SAML 2.0) web app.
.DESCRIPTION
  Creates the shared resources if they are missing (resource group, App Service plan, VNet,
  Storage), then deploys only the SAML web app. The OIDC web app is not created or changed;
  deploy it separately with deploy-oidc.ps1, using the same -ResourceGroup and -EnvironmentName.

  Run twice. The enterprise application is created in the Entra admin center, so the
  script pauses after provisioning:
    1. Without -EntryPoint/-CertificatePath: provisions Azure, deploys the code, and prints
       the values to enter in Entra.
    2. With -EntryPoint and -CertificatePath: applies the SAML settings and verifies sign-in.
  Both runs are safe to repeat.
.EXAMPLE
  .\scripts\deploy-saml.ps1 -Location eastus
  .\scripts\deploy-saml.ps1 -Location eastus -EntryPoint "https://login.microsoftonline.com/<tenant>/saml2" -CertificatePath .\entra-saml.cer
#>
param(
  [Parameter(Mandatory)][string]$Location,
  [string]$ResourceGroup = 'rg-mca-web-policy-test',
  [string]$EnvironmentName = 'mcawebpolicy',
  [string]$StorageAccountName,
  [string]$EntryPoint,
  [string]$CertificatePath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if ([bool]$EntryPoint -ne [bool]$CertificatePath) {
  throw 'Provide both -EntryPoint and -CertificatePath, or neither.'
}

$shared = Install-SharedInfrastructure -ResourceGroup $ResourceGroup -Location $Location `
  -EnvironmentName $EnvironmentName -StorageAccountName $StorageAccountName
$app = Install-WebApp -AuthProvider saml -ResourceGroup $ResourceGroup -WebAppName "$EnvironmentName-saml-web" -Shared $shared
$webApp = $app.name.value
$url = $app.url.value

$settings = New-BaseSettings -WebApp $webApp -ResourceGroup $ResourceGroup -AuthProvider saml `
  -StorageAccountName $shared.storageAccountName.value -ContainerName $shared.samlStorageContainerName.value
$settings.SAML_ISSUER = "$url/saml/metadata"
$settings.SAML_CALLBACK_URL = "$url/auth/callback"

if ($EntryPoint) {
  if (-not (Test-Path $CertificatePath)) { throw "Certificate file not found: $CertificatePath" }
  $settings.SAML_ENTRY_POINT = $EntryPoint.Trim()
  $settings.SAML_IDP_CERT = (Get-Content $CertificatePath -Raw) -replace '-----[A-Z ]+-----|\s', ''
}

Set-AppSettings -WebApp $webApp -ResourceGroup $ResourceGroup -Settings $settings
Publish-App -WebApp $webApp -ResourceGroup $ResourceGroup

if (-not $EntryPoint) {
  Test-Deployment -Url $url -AuthProvider saml -RequireAuthEnabled $false
  Write-Host ''
  Write-Host 'Azure is ready. Create the Entra enterprise application (see docs/saml-setup.md, step 2) with:'
  Write-Host "  Identifier (Entity ID): $url/saml/metadata"
  Write-Host "  Reply URL:              $url/auth/callback"
  Write-Host "  Sign-on URL:            $url/auth/login"
  Write-Host ''
  Write-Host 'Then run this script again with -EntryPoint <Login URL> -CertificatePath <Certificate (Base64) file>.'
  return
}

Test-Deployment -Url $url -AuthProvider saml
Write-Host ''
Write-Host "SAML app is ready: $url"
