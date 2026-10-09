# MCA Web Policy Test

A small Node.js app for testing Microsoft Defender for Cloud Apps (MDCA) file upload and download policies. Sign in, upload a file, download it, and observe how your policies respond.

One codebase supports two web apps that share one resource group, App Service plan, VNet, and private Storage account. Each web app has its own deployment script and is deployed on its own: running one script never creates or changes the other app, so you can deploy OIDC, SAML, or both.

| Web app | Sign-in | Deploy with | App Service | Blob container | Guide |
|---------|---------|-------------|-------------|----------------|-------|
| OIDC | Microsoft Entra ID OpenID Connect | `scripts\deploy-oidc.ps1` | `<env>-oidc-web` | `mdca-files` | [OIDC setup](docs/oidc-setup.md) |
| SAML | Microsoft Entra ID SAML 2.0 | `scripts\deploy-saml.ps1` | `<env>-saml-web` | `mdca-files-saml` | [SAML setup](docs/saml-setup.md) |

Both scripts use the default resource group `rg-mca-web-policy-test` and environment name `mcawebpolicy`, and create the shared resources only if missing. Each app uses its own managed identity to access Blob Storage; no storage keys are used.
## Quick start (local)

```powershell
npm install
Copy-Item .env.example .env
npm start
```

Open <http://localhost:3000>. With no settings filled in, the app runs with local file storage and shows that sign-in is not configured. To enable sign-in, set `AUTH_PROVIDER` and the matching values in `.env` as described in the [OIDC](docs/oidc-setup.md#test-locally-optional) or [SAML](docs/saml-setup.md#test-locally-optional) guide.

## Deploy to Azure

> [!WARNING]
> **Confirm your subscription, region, and quota before deploying.** The template creates a Basic `B1` Linux App Service plan, and the web apps run on it. `B1` is a paid tier and requires available **Basic VMs** quota in the target region, which new or restricted subscriptions often do not have.
>
> - **Subscription:** run `az account show` and make sure it is the one you intend to bill.
> - **Region:** every resource is created in the resource group's region. Pass it to the deployment script as `-Location`.
> - **Availability:** check that `B1` Linux is offered in that region: `az appservice list-locations --sku B1 --linux-workers-enabled --output table`
> - **Quota:** in the Azure portal, open **Subscriptions > your subscription > Usage + quotas**, filter by **Microsoft.Web** and your region, and confirm Basic App Service Plan capacity. Request an increase if it is zero.
> - **Region cannot be changed later:** the resource group's location and the App Service plan's region are fixed once created, so a wrong choice means deleting and redeploying.
>
> The plan SKU can be changed with `appServicePlanSku=<sku>` on the deployment command (for example `S1`), but not to `F1`, which does not support the VNet integration this template uses.

Follow the guide for the sign-in method you want (each guide is the complete process for that deployment):

- [Set up the OIDC app](docs/oidc-setup.md)
- [Set up the SAML app](docs/saml-setup.md)

## Project layout

```text
server.js          Routes, sessions, upload/download
storage.js         Blob Storage or local-folder storage
auth/              index.js picks AUTH_PROVIDER; oidc.js and saml.js are the strategies
views/, public/    Shared UI
infra/             main.bicep (shared resources) and web-app.bicep (one App Service)
scripts/deploy.ps1 Packages and deploys the app to an App Service
```

## Configuration

Settings are environment variables (`.env` locally, App Service settings in Azure). See [.env.example](.env.example).

| Setting | Purpose |
|---------|---------|
| `AUTH_PROVIDER` | `oidc` or `saml`. Defaults to `oidc` locally; required in Azure (set by the deployment scripts) |
| `SESSION_SECRET` | Signs session cookies; use a long random value |
| `AZURE_STORAGE_ACCOUNT_NAME` / `AZURE_STORAGE_CONTAINER_NAME` | Blob Storage target; leave blank locally to use `uploads/` |

`GET /health` reports `storage`, `authProvider`, and `authEnabled`, which is the quickest way to confirm a deployment is configured.

## Notes

- Use non-sensitive files for testing.
- Do not commit `.env`, client secrets, or certificates. For production, use Key Vault references for secrets.
- The Bicep template does not manage app settings, so re-running it never erases your Entra configuration. The deployment scripts set them, then confirm `/health` reports the expected `authProvider`.
- The default App Service plan is `B1`; VNet integration and Always On are not available on the free `F1` tier.
