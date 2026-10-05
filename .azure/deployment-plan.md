# Azure deployment plan

## Status
- [x] Ready for Validation

## Summary
- Project type: new web app for MDCA testing
- Target: Azure App Service (Linux Node.js runtime)
- Auth: Microsoft Entra ID OIDC (OpenID Connect with app registration)
- Storage: Azure Blob Storage for upload/download test flows
- Pattern: Azure-ready web application with local fallback for development

## Requirements
- Secure sign-in through Microsoft Entra ID using OIDC
- Simple file upload and download workflow suitable for MDCA policy testing
- Azure deployment support with minimal configuration and managed identity
- Clear setup guidance for environment variables and app registration

## Architecture
- Frontend: Express + EJS web app
- Authentication: OpenID Connect via `openid-client` and `passport`
- Storage: Azure Blob Storage, with local filesystem fallback when Azure settings are absent
- Azure hosting: App Service with Linux Node.js runtime and system-assigned managed identity
- Infrastructure: Bicep template under `infra/main.bicep` plus `azure.yaml`

## Implementation steps
- [x] Create Azure plan and project skeleton
- [x] Scaffold Node.js web app and UI
- [x] Add Entra OIDC integration points in code
- [x] Add upload/download storage layer with Azure Blob support
- [x] Add Azure infrastructure templates and deployment metadata
- [x] Validate local startup and homepage rendering

## Files to review
- `server.js` – application routing, OIDC startup, upload/download logic
- `views/index.ejs` – UI for login, upload, and download actions
- `public/styles.css` – styling for the test site
- `infra/main.bicep` – Azure App Service and storage resources
- `azure.yaml` – Azure Developer CLI service definition
- `README.md` – deployment and configuration instructions

## Deployment guidance
1. Create a Microsoft Entra web app registration and configure redirect URIs.
2. Set `AAD_TENANT_ID`, `AAD_CLIENT_ID`, `AAD_CLIENT_SECRET`, and `OIDC_ISSUER` in App Service settings.
3. Configure `AZURE_STORAGE_ACCOUNT_NAME` plus either `AZURE_STORAGE_CONNECTION_STRING` or managed identity with Storage Blob Data Contributor.
4. Deploy the app to Azure App Service using `azd up` or standard App Service deployment.
5. Validate the app by signing in, uploading a file, and downloading it to confirm file policy testing flows.
