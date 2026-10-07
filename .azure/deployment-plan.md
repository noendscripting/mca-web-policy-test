# Azure deployment plan

## Status
- [x] Ready for Validation

## Summary
- Mode: MODIFY an existing Azure-ready web app
- Change scope: documentation only
- Project type: Node.js/Express web app for MDCA testing
- Target: Azure App Service (Linux Node.js runtime)
- Auth: Microsoft Entra ID OIDC (OpenID Connect with app registration)
- Storage: Azure Blob Storage for upload/download test flows
- Infrastructure: existing resource-group-scoped Bicep template
- Deployment methods to document: direct Bicep deployment through Azure CLI and imperative Azure CLI application deployment

## Requirements
- Preserve the existing application and infrastructure.
- Add detailed prerequisites, authentication, subscription selection, naming, and Entra app registration guidance.
- Document resource provisioning with `az deployment group create` and `infra/main.bicep`.
- Document application packaging and App Service ZIP deployment using Azure CLI.
- Document required App Service settings, managed identity behavior, deployment verification, log access, updates, troubleshooting, and cleanup.
- Use the existing Bicep outputs so commands can be copied without manually rediscovering resource names.

## Architecture
- Frontend: Express + EJS web app
- Authentication: OpenID Connect via `openid-client` and `passport`
- Storage: Azure Blob Storage, with local filesystem fallback when Azure settings are absent
- Azure hosting: App Service with Linux Node.js runtime and system-assigned managed identity
- Infrastructure: `infra/main.bicep` provisions a Linux F1 App Service plan for low-cost dev/test workloads, Node.js App Service, dedicated VNet and subnets, Blob private endpoint and private DNS, a StorageV2 account with public network access disabled, a private blob container, system-assigned managed identity, and Storage Blob Data Contributor role assignment
- Health endpoint: `/health`
- Existing AZD metadata: `azure.yaml`; this documentation change focuses on the requested Bicep and `az` CLI workflows

## Implementation steps
- [x] Inspect the application, Bicep template, environment example, and Azure metadata
- [x] Confirm no specialized Copilot SDK routing applies
- [x] Select the existing Bicep + Azure CLI deployment recipe
- [x] Expand `README.md` with the complete deployment workflow
- [x] Verify all documented commands against the template parameters, outputs, application settings, and health endpoint

## Files to review
- `server.js` – application routing, OIDC startup, upload/download logic
- `views/index.ejs` – UI for login, upload, and download actions
- `public/styles.css` – styling for the test site
- `infra/main.bicep` – Azure App Service and storage resources
- `azure.yaml` – Azure Developer CLI service definition
- `README.md` – deployment and configuration instructions

## Deployment guidance
1. Install and authenticate Azure CLI, then select the target subscription.
2. Create the resource group and deploy `infra/main.bicep` with explicit environment, SKU, and private network address parameters.
3. Capture `webAppName`, `webAppUrl`, and storage outputs from the deployment.
4. Create/configure the Entra web app registration and client secret.
5. Configure App Service OIDC and session settings without placing secrets in source control.
6. Create a clean ZIP package excluding local dependencies, secrets, Git metadata, and uploads.
7. Deploy the package with `az webapp deploy`.
8. Verify `/health`, sign-in, upload/download behavior, managed identity role assignment, and logs.
9. Document repeat deployments, troubleshooting, and optional resource-group cleanup.

## Validation checks
- [x] Bicep compilation
- [x] Azure CLI ZIP deployment flags
- [x] Static role assignment verification
- [x] README deployment workflow and command references
- [ ] Azure template validation against a selected subscription and resource group (deferred until an actual deployment is requested)
- [ ] Azure what-if and policy validation (deferred until an actual deployment is requested)

## Role assignment verification
- Status: Verified statically
- Identity: App Service system-assigned managed identity
- Role: Storage Blob Data Contributor (`ba92f5b4-2d11-453d-a403-e96b0029c9fe`)
- Scope: The application storage account
- Code operations covered: create the private container if needed, list blobs, upload blobs, read blob properties, and download blobs

## Validation proof
- `az bicep build --file .\infra\main.bicep --stdout`: passed
- `az webapp deploy --help`: confirmed support for the documented `--src-path`, `--type`, `--clean`, and `--restart` arguments
- Static RBAC review: the managed identity role and storage-account scope match the Blob data-plane operations in `server.js`
- No live Azure validation or deployment was run because this change is documentation-only and no target subscription, resource group, or location was approved for deployment
