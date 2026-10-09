param(
  [Parameter(Mandatory)][string]$WebAppName,
  [Parameter(Mandatory)][string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

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
