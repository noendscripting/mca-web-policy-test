param(
  [Parameter(Mandatory)][string]$WebAppName,
  [Parameter(Mandatory)][string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

# Zip deploy authenticates to SCM with basic auth. web-app.bicep sets this too; repeating it
# here lets this script also redeploy code to an app whose setting was turned off later.
az resource update --resource-group $ResourceGroup --namespace Microsoft.Web `
  --parent "sites/$WebAppName" --resource-type basicPublishingCredentialsPolicies --name scm `
  --api-version 2023-01-01 --set properties.allow=true --output none
if ($LASTEXITCODE) {
  throw 'Could not enable SCM Basic Auth Publishing Credentials (permissions or an Azure Policy). Code was not uploaded.'
}

$package = Join-Path ([IO.Path]::GetTempPath()) 'mca-web-policy-test.zip'
Remove-Item $package -ErrorAction SilentlyContinue

# tar writes forward-slash paths, which Linux App Service requires.
tar -a -cf $package server.js storage.js auth package.json package-lock.json public views
if ($LASTEXITCODE) { throw 'Packaging failed.' }

try {
  az webapp deploy --name $WebAppName --resource-group $ResourceGroup --src-path $package --type zip --clean true --restart true --output table
  if ($LASTEXITCODE) { throw 'Deployment failed.' }
}
finally {
  Remove-Item $package -ErrorAction SilentlyContinue
}
