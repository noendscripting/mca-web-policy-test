# Set up the OIDC app

Deploys the Microsoft Entra ID **OpenID Connect** web app. The OIDC and SAML web apps share one resource group, App Service plan, VNet, and Storage account, but they are separate web apps with separate deployment scripts. This script deploys only the OIDC app; run [deploy-saml.ps1](saml-setup.md) as well only if you also want the SAML app.

**You need:** an Azure subscription with Owner (or Contributor + User Access Administrator), permission to create Entra app registrations, [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), and PowerShell. A region with `B1` quota is required; see the warning in the [README](../README.md#deploy-to-azure).

## Deploy

Run from the repository root:

```powershell
az login
az account set --subscription "<subscription-id>"

.\scripts\deploy-oidc.ps1 -Location eastus   # change to your region
```

The script is safe to re-run. It:

1. Creates the shared resources if missing (resource group `rg-mca-web-policy-test`, plan, VNet, private Storage account, containers) by deploying `infra/main.bicep`. This step never creates or changes a web app, and it is safe if the SAML app already exists.
2. Deploys only the OIDC web app `mcawebpolicy-oidc-web` with `infra/web-app.bicep`, using the container `mdca-files`.
3. Creates (or reuses) the Entra app registration `mca-web-policy-oidc`, its service principal (so MDCA can evaluate the app), the `api://<client-id>` identifier URI, and the `access_as_user` scope that sign-in requests.
4. Creates a client secret and sets all app settings, including `AUTH_PROVIDER=oidc`, in one step.
5. Deploys the code and checks `/health` until it reports `authProvider=oidc` and `authEnabled=True`.

Optional parameters: `-ResourceGroup`, `-EnvironmentName` (app names must be globally unique, so change it if `mcawebpolicy-oidc-web` is taken), `-StorageAccountName`, `-AppDisplayName`. If you also deploy the SAML app, pass the same `-ResourceGroup`, `-EnvironmentName`, and `-StorageAccountName` to both scripts.

## Verify

Open the URL printed at the end, sign in, upload a non-sensitive file, confirm it is listed, download it, and check the MDCA activity log and policy behavior.

The client secret is stored only in App Service settings and cannot be retrieved later; re-running the script creates a new one. For production, use a Key Vault reference.

## Test locally (optional)

Add `http://localhost:3000/auth/callback` as a **Web** redirect URI on the app registration, then set these in `.env`:

```env
AUTH_PROVIDER=oidc
AAD_TENANT_ID=<tenant-id>
AAD_CLIENT_ID=<client-id>
AAD_CLIENT_SECRET=<client-secret>
```

Run `npm start` and open <http://localhost:3000>.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `authEnabled: False` | Run `az webapp config appsettings list` and confirm `AUTH_PROVIDER=oidc`, `AAD_*`, and `OIDC_REDIRECT_URI`; view the logs for the reason. |
| Page says `AUTH_PROVIDER is not set` | The settings were never applied. Re-run `deploy-oidc.ps1`. |
| Redirect URI error from Entra | The redirect URI on the app registration must exactly match `<app url>/auth/callback`. |
| Scope or consent error | The `access_as_user` scope exists and the Application ID URI is `api://<client-id>` (**Expose an API**). |
| `storage: local` or blob errors | `AZURE_STORAGE_*` settings exist, and the app's managed identity has `Storage Blob Data Contributor` on the storage account. |
| App does not start | `az webapp log tail --name <web app> --resource-group <resource group>` |

To redeploy after code changes, run `deploy-oidc.ps1` again. To remove only this app: `az webapp delete --name mcawebpolicy-oidc-web --resource-group rg-mca-web-policy-test`. To remove everything, including the SAML app: `az group delete --name rg-mca-web-policy-test`.
