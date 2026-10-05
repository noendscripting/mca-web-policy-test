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

Then set these environment variables:

```env
AAD_TENANT_ID=<tenant-id>
AAD_CLIENT_ID=<app-registration-client-id>
AAD_CLIENT_SECRET=<client-secret>
OIDC_ISSUER=https://login.microsoftonline.com/<tenant-id>/v2.0
OIDC_REDIRECT_URI=http://localhost:3000/auth/callback
```

## Azure deployment

The repository includes Azure infrastructure via `infra/main.bicep` and `azure.yaml` for use with Azure Developer CLI or App Service deployment workflows.

### Azure App Service configuration

For deployed environments, configure the App Service app settings:

- `AAD_TENANT_ID`
- `AAD_CLIENT_ID`
- `AAD_CLIENT_SECRET`
- `OIDC_ISSUER`
- `OIDC_REDIRECT_URI`
- `AZURE_STORAGE_CONNECTION_STRING` or `AZURE_STORAGE_ACCOUNT_NAME` (with managed identity)
- `AZURE_STORAGE_CONTAINER_NAME=mdca-files`

For managed identity with Azure Storage, enable a system-assigned identity on the App Service and grant it the `Storage Blob Data Contributor` role on the storage account.

## Testing scenarios

The site is useful for validating how Microsoft Defender for Cloud Apps handles:

- Uploading a file to an internal cloud app
- Downloading a file from the portal
- Restricting or allowing file access based on policy conditions
- Monitoring user-driven file movement activity

## Notes

- Without Azure Storage configuration, the app falls back to a local uploads folder so it can still run in a dev environment.
- When OIDC settings are not supplied, the app will display a configuration alert but still serve the local page.
