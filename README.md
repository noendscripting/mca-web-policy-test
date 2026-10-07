# MCA Web Policy Test

This project is a lightweight Azure-ready web app designed for testing Microsoft Defender for Cloud Apps file upload and download policy controls. It includes:

- Microsoft Entra ID OIDC authentication
- A secure file upload/download workflow backed by Azure Blob Storage
- A simple dashboard to validate whether file movement is allowed or blocked by policy
- Azure deployment support with App Service and Bicep templates

## Local development

1. Install dependencies:
   
   ```bash
   npm install
   ```

2. Copy the example environment file:
   
   ```bash
   cp .env.example .env
   ```

3. Update the values in `.env` for your Entra app registration and Azure storage resources.

4. Start the app:
   
   ```bash
   npm start
   ```

5. Open http://localhost:3000

## Configuring Microsoft Entra ID OIDC

Create an app registration in Microsoft Entra admin center:

- Type: Web
- Redirect URI: `http://localhost:3000/auth/callback` for local testing and `https://<your-app-name>.azurewebsites.net/auth/callback` for Azure
- Allowed token audiences: the application ID URI or the configured client ID
- Authentication method: Secret or certificate
- Required for MDCA: create a Microsoft Entra service principal for this app registration so MDCA can authenticate and evaluate the app as a service principal object in the tenant.

Then set these environment variables:

```env
AAD_TENANT_ID=<tenant-id>
AAD_CLIENT_ID=<app-registration-client-id>
AAD_CLIENT_SECRET=<client-secret>
OIDC_ISSUER=https://login.microsoftonline.com/<tenant-id>/v2.0
OIDC_REDIRECT_URI=http://localhost:3000/auth/callback
```

## Azure deployment

The application runs on a Linux Azure App Service with Node.js 20 and uses Azure Blob Storage for files. You can provision the resources with either:

- [Option A: Bicep](#option-a-provision-with-bicep-recommended), which deploys the checked-in `infra/main.bicep` template.
- [Option B: Azure CLI only](#option-b-provision-with-azure-cli-only), which creates the equivalent resources imperatively.

Both options use a system-assigned managed identity for Blob Storage authorization and Private Link for network access. The storage account has public network access disabled, so no storage account key, connection string, or public endpoint access is required.

### Prerequisites

- An Azure subscription.
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) 2.60 or later.
- PowerShell 7 or Windows PowerShell 5.1 for the commands below.
- Node.js 20 and npm for local validation.
- Permission to create resource groups, virtual networks, private endpoints, private DNS zones, App Service resources, storage accounts, managed identities, and role assignments. `Owner` or `Contributor` plus `User Access Administrator` on the target scope is sufficient.
- Permission to create a Microsoft Entra app registration, or an app registration supplied by an Entra administrator.
- A Microsoft Entra service principal for the app registration so Microsoft Defender for Cloud Apps (MDCA) can authenticate to the application and evaluate the sign-in context. If the app registration is created in Azure CLI, create the service principal with `az ad sp create --id $ClientId` after the app object exists.

Run all commands from the repository root. Sign in and select the target subscription:

```powershell
az login
az account list --output table

$SubscriptionId = "<subscription-id>"
az account set --subscription $SubscriptionId
az account show --query "{subscription:name, subscriptionId:id, tenantId:tenantId}" --output table
```

Choose deployment values. App Service names and storage account names must be globally unique. The Bicep option generates a unique storage account name automatically, while the CLI-only option requires one.

```powershell
$Location = "southcentralus"
$ResourceGroup = "rg-mca-web-policy-test"
$EnvironmentName = "mcawebpolicy"
$DeploymentName = "mca-web-policy-test"
$VirtualNetworkName = "$EnvironmentName-vnet"
$VirtualNetworkAddressPrefix = "10.20.0.0/16"
$AppServiceIntegrationSubnetName = "app-service-integration"
$AppServiceIntegrationSubnetAddressPrefix = "10.20.0.0/26"
$PrivateEndpointSubnetName = "private-endpoints"
$PrivateEndpointSubnetAddressPrefix = "10.20.0.64/27"
```

To see which Azure regions are available to the subscription:

```powershell
az account list-locations --query "[].{Name:name, DisplayName:displayName}" --output table
```

### Option A: provision with Bicep (recommended)

The `infra/main.bicep` template creates:

- A Linux F1 App Service plan for low-cost dev/test use.
- A Node.js 20 App Service named `<environmentName>-web`.
- A StorageV2 account and private `mdca-files` blob container.
- A system-assigned managed identity for the web app.
- A `Storage Blob Data Contributor` role assignment for that identity.
- A dedicated VNet with separate App Service integration and private endpoint subnets.
- App Service regional VNet integration through the delegated integration subnet.
- A Blob private endpoint in the private endpoint subnet.
- A `privatelink.blob.core.windows.net` private DNS zone linked to the new VNet.
- A storage firewall configuration that disables all public network access.

The Bicep template defines both subnets inline with the VNet so repeat deployments preserve subnets that are already in use by App Service and Private Link.

Create the resource group:

```powershell
az group create `
  --name $ResourceGroup `
  --location $Location `
  --output table
```

Optional: preview the changes before deployment:

```powershell
az deployment group what-if `
  --resource-group $ResourceGroup `
  --template-file .\infra\main.bicep `
  --parameters environmentName=$EnvironmentName location=$Location appServicePlanSku=F1 `
    virtualNetworkAddressPrefix=$VirtualNetworkAddressPrefix `
    appServiceIntegrationSubnetAddressPrefix=$AppServiceIntegrationSubnetAddressPrefix `
    privateEndpointSubnetAddressPrefix=$PrivateEndpointSubnetAddressPrefix
```

Deploy the Bicep template and capture its outputs:

```powershell
$Outputs = az deployment group create `
  --name $DeploymentName `
  --resource-group $ResourceGroup `
  --template-file .\infra\main.bicep `
  --parameters environmentName=$EnvironmentName location=$Location appServicePlanSku=F1 `
    virtualNetworkAddressPrefix=$VirtualNetworkAddressPrefix `
    appServiceIntegrationSubnetAddressPrefix=$AppServiceIntegrationSubnetAddressPrefix `
    privateEndpointSubnetAddressPrefix=$PrivateEndpointSubnetAddressPrefix `
  --query properties.outputs `
  --output json | ConvertFrom-Json

$WebAppName = $Outputs.webAppName.value
$WebAppUrl = $Outputs.webAppUrl.value
$StorageAccountName = $Outputs.storageAccountName.value
$StorageContainerName = $Outputs.storageContainerName.value

$Outputs | ConvertTo-Json
```

If the role assignment fails with an authorization error, ask an administrator to grant you `Microsoft.Authorization/roleAssignments/write` permission and rerun the same deployment.

Continue with [Configure Microsoft Entra ID](#configure-microsoft-entra-id).

### Option B: provision with Azure CLI only

Use this option when you cannot use Bicep or need to create the resources one command at a time.

Set globally unique names. Storage account names must contain only lowercase letters and numbers and be between 3 and 24 characters.

```powershell
$WebAppName = "<globally-unique-app-name>"
$AppServicePlanName = "$EnvironmentName-plan"
$StorageAccountName = "<globallyuniquestorage>"
$StorageContainerName = "mdca-files"
$WebAppUrl = "https://$WebAppName.azurewebsites.net"
$PrivateEndpointName = "$EnvironmentName-storage-blob-pe"
$PrivateDnsZoneName = "privatelink.blob.core.windows.net"
```

Check name availability:

```powershell
az webapp list --query "[?name=='$WebAppName'].name" --output tsv
az storage account check-name --name $StorageAccountName --output table
```

Create the resource group and dedicated VNet:

```powershell
az group create `
  --name $ResourceGroup `
  --location $Location `
  --output table

az network vnet create `
  --name $VirtualNetworkName `
  --resource-group $ResourceGroup `
  --location $Location `
  --address-prefixes $VirtualNetworkAddressPrefix `
  --output none

az network vnet subnet create `
  --name $AppServiceIntegrationSubnetName `
  --resource-group $ResourceGroup `
  --vnet-name $VirtualNetworkName `
  --address-prefixes $AppServiceIntegrationSubnetAddressPrefix `
  --delegations Microsoft.Web/serverFarms `
  --output none

az network vnet subnet create `
  --name $PrivateEndpointSubnetName `
  --resource-group $ResourceGroup `
  --vnet-name $VirtualNetworkName `
  --address-prefixes $PrivateEndpointSubnetAddressPrefix `
  --disable-private-endpoint-network-policies true `
  --output none

$VirtualNetworkId = az network vnet show `
  --name $VirtualNetworkName `
  --resource-group $ResourceGroup `
  --query id `
  --output tsv

$AppServiceIntegrationSubnetId = az network vnet subnet show `
  --ids "$VirtualNetworkId/subnets/$AppServiceIntegrationSubnetName" `
  --query id `
  --output tsv

$PrivateEndpointSubnetId = az network vnet subnet show `
  --ids "$VirtualNetworkId/subnets/$PrivateEndpointSubnetName" `
  --query id `
  --output tsv
```

Create the storage account, App Service plan, and web app:

```powershell
az storage account create `
  --name $StorageAccountName `
  --resource-group $ResourceGroup `
  --location $Location `
  --sku Standard_LRS `
  --kind StorageV2 `
  --access-tier Hot `
  --https-only true `
  --min-tls-version TLS1_2 `
  --allow-blob-public-access false `
  --public-network-access Disabled `
  --output table

az rest `
  --method put `
  --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccountName/blobServices/default/containers/$StorageContainerName?api-version=2023-05-01" `
  --body '{"properties":{"publicAccess":"None"}}' `
  --output none

az appservice plan create `
  --name $AppServicePlanName `
  --resource-group $ResourceGroup `
  --location $Location `
  --is-linux `
  --sku B1 `
  --output table

az webapp create `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --plan $AppServicePlanName `
  --runtime "NODE:20-lts" `
  --output table

az webapp update `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --https-only true `
  --output none
```

Connect the web app and storage account through the new VNet:

```powershell
$StorageAccountId = az storage account show `
  --name $StorageAccountName `
  --resource-group $ResourceGroup `
  --query id `
  --output tsv

az webapp vnet-integration add `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --vnet $VirtualNetworkId `
  --subnet $AppServiceIntegrationSubnetId `
  --output none

az webapp config set `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --generic-configurations '{"vnetRouteAllEnabled":true}' `
  --output none

az network private-endpoint create `
  --name $PrivateEndpointName `
  --resource-group $ResourceGroup `
  --location $Location `
  --vnet-name $VirtualNetworkId `
  --subnet $PrivateEndpointSubnetId `
  --private-connection-resource-id $StorageAccountId `
  --group-id blob `
  --connection-name "$EnvironmentName-storage-blob-connection" `
  --output none

az network private-dns zone create `
  --resource-group $ResourceGroup `
  --name $PrivateDnsZoneName `
  --output none

az network private-dns link vnet create `
  --resource-group $ResourceGroup `
  --zone-name $PrivateDnsZoneName `
  --name "$EnvironmentName-blob-vnet-link" `
  --virtual-network $VirtualNetworkId `
  --registration-enabled false `
  --output none

$PrivateDnsZoneId = az network private-dns zone show `
  --resource-group $ResourceGroup `
  --name $PrivateDnsZoneName `
  --query id `
  --output tsv

az network private-endpoint dns-zone-group create `
  --resource-group $ResourceGroup `
  --endpoint-name $PrivateEndpointName `
  --name default `
  --private-dns-zone $PrivateDnsZoneId `
  --zone-name blob `
  --output none
```

Enable the web app's managed identity and grant it access to Blob Storage:

```powershell
$PrincipalId = az webapp identity assign `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --query principalId `
  --output tsv

az role assignment create `
  --assignee-object-id $PrincipalId `
  --assignee-principal-type ServicePrincipal `
  --role "Storage Blob Data Contributor" `
  --scope $StorageAccountId `
  --output table
```

Configure the storage settings:

```powershell
az webapp config appsettings set `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --settings `
    AZURE_STORAGE_ACCOUNT_NAME=$StorageAccountName `
    AZURE_STORAGE_CONTAINER_NAME=$StorageContainerName `
  --output none
```

### Configure Microsoft Entra ID

The application uses OIDC and requires a confidential Microsoft Entra web app registration.

#### Create an app registration with Azure CLI

Get the current tenant ID and create the registration with the deployed callback URL:

```powershell
$TenantId = az account show --query tenantId --output tsv
$RedirectUri = "$WebAppUrl/auth/callback"

$ClientId = az ad app create `
  --display-name "$EnvironmentName-oidc" `
  --sign-in-audience AzureADMyOrg `
  --web-redirect-uris $RedirectUri `
  --enable-id-token-issuance true `
  --query appId `
  --output tsv

$ServicePrincipalId = az ad sp create --id $ClientId --query id --output tsv

$ClientSecret = az ad app credential reset `
  --id $ClientId `
  --append `
  --display-name "app-service" `
  --years 1 `
  --query password `
  --output tsv
```

Save the client secret immediately in an approved password manager. It cannot be retrieved later. Do not add it to `.env`, source control, shell profiles, or deployment scripts.

The service principal is required for Microsoft Defender for Cloud Apps (MDCA) integration and to ensure the app registration exists as an Entra service principal object that policy evaluation can reference.

If your organization does not allow app registration creation, give an Entra administrator these values:

- Platform: **Web**
- Redirect URI: `<web-app-url>/auth/callback`
- Supported account type: **Accounts in this organizational directory only**
- Token: **ID tokens**

The administrator must then provide the application (client) ID and a client secret.

#### Configure App Service settings

Generate a session secret and configure the web app:

```powershell
$SessionSecret = -join ((1..64) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })

az webapp config appsettings set `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --settings `
    NODE_ENV=production `
    SESSION_SECRET=$SessionSecret `
    AAD_TENANT_ID=$TenantId `
    AAD_CLIENT_ID=$ClientId `
    AAD_CLIENT_SECRET=$ClientSecret `
    OIDC_ISSUER="https://login.microsoftonline.com/$TenantId/v2.0" `
    OIDC_REDIRECT_URI=$RedirectUri `
    AZURE_STORAGE_ACCOUNT_NAME=$StorageAccountName `
    AZURE_STORAGE_CONTAINER_NAME=$StorageContainerName `
    SCM_DO_BUILD_DURING_DEPLOYMENT=true `
  --output none
```

App Service stores app settings encrypted at rest and exposes them to the application as environment variables. For a production deployment, prefer a Key Vault reference for `AAD_CLIENT_SECRET` and define a secret-rotation process.

### Package and deploy the application

Validate the application before packaging:

```powershell
npm ci
npm start
```

Open `http://localhost:3000/health`, then stop the local process with `Ctrl+C`.

Create a deployment package containing only the files required at runtime:

```powershell
Remove-Item .\deploy.zip -ErrorAction SilentlyContinue
Compress-Archive `
  -Path .\server.js, .\package.json, .\package-lock.json, .\public, .\views `
  -DestinationPath .\deploy.zip
```

Deploy the ZIP package. `SCM_DO_BUILD_DURING_DEPLOYMENT=true` causes App Service to run `npm install` from `package-lock.json` during deployment.

```powershell
az webapp deploy `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --src-path .\deploy.zip `
  --type zip `
  --clean true `
  --restart true `
  --output table
```

Delete the local package after deployment:

```powershell
Remove-Item .\deploy.zip
```

### Verify the deployment

Check the health endpoint:

```powershell
Invoke-RestMethod "$WebAppUrl/health"
```

Expected fields:

```text
status      : ok
storage     : blob
oidcEnabled : True
```

Open the site and complete an end-to-end test:

```powershell
Start-Process $WebAppUrl
```

1. Select **Sign in** and complete Microsoft Entra authentication.
2. Upload a non-sensitive test file.
3. Confirm that the file appears in the list.
4. Download the file and verify that the expected Defender for Cloud Apps policy is applied.

Confirm that the managed identity role assignment exists:

```powershell
az role assignment list `
  --assignee $PrincipalId `
  --scope $StorageAccountId `
  --query "[].{Role:roleDefinitionName, Scope:scope}" `
  --output table
```

For Bicep deployments, populate `$PrincipalId` and `$StorageAccountId` first:

```powershell
$PrincipalId = az webapp identity show `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --query principalId `
  --output tsv

$StorageAccountId = az storage account show `
  --name $StorageAccountName `
  --resource-group $ResourceGroup `
  --query id `
  --output tsv
```

### Logs and troubleshooting

Enable and stream App Service application logs:

```powershell
az webapp log config `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --application-logging filesystem `
  --level information `
  --web-server-logging filesystem

az webapp log tail `
  --name $WebAppName `
  --resource-group $ResourceGroup
```

Common issues:

| Symptom | Check |
| --- | --- |
| Deployment succeeds but the app does not start | Confirm `SCM_DO_BUILD_DURING_DEPLOYMENT=true`, inspect the log stream, and verify the runtime with `az webapp config show --name $WebAppName --resource-group $ResourceGroup --query linuxFxVersion`. |
| Health reports `oidcEnabled: false` | Verify all `AAD_*`, `OIDC_ISSUER`, and `OIDC_REDIRECT_URI` settings. The redirect URI must exactly match the URI on the Entra app registration. |
| Sign-in returns a redirect URI error | Add `https://<app-name>.azurewebsites.net/auth/callback` to the app registration's **Web** redirect URIs. URI matching is case-sensitive. |
| Deployment reports `InUseSubnetCannotBeDeleted` for `app-service-integration` | Use the current Bicep template and rerun the deployment. Its VNet declaration preserves both in-use subnets during repeat deployments. |
| Startup fails on a container `PUT` with HTTP 403 and an `x-ms-blob-public-access` request header | Redeploy the current application code. Blob containers are created without requesting public access because the storage account sets `allowBlobPublicAccess` to `false`. |
| Storage operations return HTTP 403 while public network access is disabled | Confirm the App Service has VNet integration, the Blob private endpoint connection is approved, and `<storage-account>.blob.core.windows.net` resolves to the private endpoint IP from the App Service. |
| Storage still returns HTTP 403 after private connectivity is verified | Confirm the App Service identity has `Storage Blob Data Contributor` on the storage account. New role assignments can take several minutes to propagate. |
| Health reports `storage: local` | Verify `AZURE_STORAGE_ACCOUNT_NAME` is set and restart the app with `az webapp restart --name $WebAppName --resource-group $ResourceGroup`. |
| The client secret expires | Create a new app-registration credential, update `AAD_CLIENT_SECRET`, restart the app, and remove the expired credential. |

List the current app-setting names without displaying their values:

```powershell
az webapp config appsettings list `
  --name $WebAppName `
  --resource-group $ResourceGroup `
  --query "[].name" `
  --output table
```

### Deploy updates

For application-only changes, repeat the steps in [Package and deploy the application](#package-and-deploy-the-application).

For infrastructure changes, preview and redeploy the Bicep template:

```powershell
az deployment group what-if `
  --resource-group $ResourceGroup `
  --template-file .\infra\main.bicep `
  --parameters environmentName=$EnvironmentName location=$Location appServicePlanSku=F1 `
    virtualNetworkAddressPrefix=$VirtualNetworkAddressPrefix `
    appServiceIntegrationSubnetAddressPrefix=$AppServiceIntegrationSubnetAddressPrefix `
    privateEndpointSubnetAddressPrefix=$PrivateEndpointSubnetAddressPrefix

az deployment group create `
  --name $DeploymentName `
  --resource-group $ResourceGroup `
  --template-file .\infra\main.bicep `
  --parameters environmentName=$EnvironmentName location=$Location appServicePlanSku=F1 `
    virtualNetworkAddressPrefix=$VirtualNetworkAddressPrefix `
    appServiceIntegrationSubnetAddressPrefix=$AppServiceIntegrationSubnetAddressPrefix `
    privateEndpointSubnetAddressPrefix=$PrivateEndpointSubnetAddressPrefix `
  --output table
```

### Clean up

Deleting the resource group permanently deletes the web app, uploaded blobs, storage account, and all other resources in the group. Review the resources first:

```powershell
az resource list --resource-group $ResourceGroup --output table
```

When you are certain the environment is no longer needed:

```powershell
az group delete --name $ResourceGroup --yes --no-wait
```

## Testing scenarios

The site is useful for validating how Microsoft Defender for Cloud Apps handles:

- Uploading a file to an internal cloud app
- Downloading a file from the portal
- Restricting or allowing file access based on policy conditions
- Monitoring user-driven file movement activity

## Notes

- Without Azure Storage configuration, the app falls back to a local uploads folder so it can still run in a dev environment.
- When OIDC settings are not supplied, the app will display a configuration alert but still serve the local page.
