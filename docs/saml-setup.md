# Set up the SAML app

Deploys the Microsoft Entra ID **SAML 2.0** web app. The SAML and OIDC web apps share one resource group, App Service plan, VNet, and Storage account, but they are separate web apps with separate deployment scripts. This script deploys only the SAML app; run [deploy-oidc.ps1](oidc-setup.md) as well only if you also want the OIDC app. If you deploy both, pass the same `-ResourceGroup`, `-EnvironmentName`, and `-StorageAccountName` to both scripts.

**You need:**

- An Azure subscription with Owner (or Contributor + User Access Administrator).
- Permission to create Entra **enterprise applications** (for example Cloud Application Administrator), or an administrator to do step 2 for you.
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and PowerShell.
- A region with `B1` quota. See the warning in the [README](../README.md#deploy-to-azure).

SAML is configured on an Entra **enterprise application** in the admin center, so deployment is two runs of the same script with that step between them. Run everything from the repository root.

## 1. Provision Azure and deploy the code

```powershell
az login
az account set --subscription "<subscription-id>"

.\scripts\deploy-saml.ps1 -Location eastus   # change to your region
```

The script creates the shared resources if missing (resource group `rg-mca-web-policy-test`, plan, VNet, private Storage account, containers), deploys only the SAML web app `mcawebpolicy-saml-web` (container `mdca-files-saml`), sets `AUTH_PROVIDER=saml` and the other base settings, deploys the code, and prints:

```text
Identifier (Entity ID): https://<app>.azurewebsites.net/saml/metadata
Reply URL:              https://<app>.azurewebsites.net/auth/callback
Sign-on URL:            https://<app>.azurewebsites.net/auth/login
```

It never creates or changes the OIDC app. Optional parameters: `-ResourceGroup`, `-EnvironmentName` (app names must be globally unique, so change it if `mcawebpolicy-saml-web` is taken), `-StorageAccountName`.

At this point the site runs as SAML and shows that SAML is not configured yet. That is expected.

## 2. Create the Entra enterprise application

Use **Enterprise applications**, not **App registrations** (that is the OIDC path).

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com).
2. Go to **Entra ID > Enterprise apps**, then select **New application > Create your own application**.
3. Enter the name `mca-web-policy-saml`, choose **Integrate any other application you don't find in the gallery (Non-gallery)**, then select **Create**.
4. Open **Single sign-on** and select **SAML**.
5. In **Basic SAML Configuration**, select **Edit** and enter the three values printed in step 1:

   | Field | Value |
   |-------|-------|
   | Identifier (Entity ID) | the `Identifier (Entity ID)` |
   | Reply URL (Assertion Consumer Service URL) | the `Reply URL` |
   | Sign-on URL | the `Sign-on URL` |

   Select **Save**. The Identifier must be unique in your tenant.
6. **Attributes & Claims**: the defaults are fine. The app reads the Name ID plus email, display name, and groups when present.
7. **Users and groups > Add user/group**: assign everyone who should sign in. Unassigned users are rejected by Entra.
8. On **Single sign-on**, in **SAML Certificates**, download **Certificate (Base64)** and save it as `entra-saml.cer` in the repository root.
9. In **Set up mca-web-policy-saml**, copy the **Login URL**.

## 3. Apply the SAML settings

Run the same script again with the Login URL and certificate:

```powershell
.\scripts\deploy-saml.ps1 -Location eastus `
  -EntryPoint "<paste the Login URL>" `
  -CertificatePath .\entra-saml.cer

Remove-Item .\entra-saml.cer
```

Use the same `-Location`, `-ResourceGroup`, and other values as in step 1. The script sets the SAML settings, redeploys, and checks `/health` until it reports `authProvider=saml` and `authEnabled=True`.

## 4. Verify

Open the app URL, sign in with an assigned user, upload a non-sensitive file, confirm it is listed, download it, and check the MDCA activity log and policy behavior. The first sign-in may take a few seconds while the app starts.

## Test locally (optional)

In the enterprise application's **Basic SAML Configuration**, add `http://localhost:3000/saml/metadata` as an additional **Identifier** and `http://localhost:3000/auth/callback` as an additional **Reply URL**. Then set these in `.env`:

```env
AUTH_PROVIDER=saml
SAML_ENTRY_POINT=<Login URL>
SAML_IDP_CERT=<base64 certificate on one line>
```

Run `npm start` and open <http://localhost:3000>.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Page says `AUTH_PROVIDER is not set` or `/health` shows `authProvider: oidc` | The settings were never applied to this app. Re-run `deploy-saml.ps1`. |
| `authEnabled: False` | Step 3 has not run, or `SAML_ENTRY_POINT`, `SAML_ISSUER`, and `SAML_IDP_CERT` are missing: `az webapp config appsettings list --name <web app> --resource-group <resource group>`. |
| Default Azure "app is running" page | Code was not deployed. Re-run `deploy-saml.ps1`. |
| Entra reply URL or audience error | Reply URL must equal `SAML_CALLBACK_URL` and Identifier must equal `SAML_ISSUER`, exactly (scheme, host, path, no trailing slash). |
| Entra says the user is not assigned | Add the user or group under **Users and groups** on the enterprise application. |
| Login returns to the home page signed out | Certificate mismatch or expiry. Download the current **Certificate (Base64)** and run step 3 again. |
| `storage: local` or blob errors | `AZURE_STORAGE_*` settings exist, and the app's managed identity has `Storage Blob Data Contributor` on the storage account. |
| App does not start | `az webapp log tail --name <web app> --resource-group <resource group>` |

To redeploy after code changes, run step 3 again. To remove only this app: `az webapp delete --name mcawebpolicy-saml-web --resource-group rg-mca-web-policy-test`. To remove everything, including the OIDC app: `az group delete --name rg-mca-web-policy-test`.
