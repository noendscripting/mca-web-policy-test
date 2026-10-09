# Azure deployment plan

## Status
- [x] Ready for Validation

## Summary
- Project: Node.js/Express app for testing Microsoft Defender for Cloud Apps upload/download policies
- Deployments: one codebase, two web apps in one resource group sharing the plan, VNet, and Storage; deployed independently by `scripts/deploy-oidc.ps1` and `scripts/deploy-saml.ps1`, each app selected by `AUTH_PROVIDER` (`oidc` or `saml`)
- Target: Azure App Service (Linux, Node.js 22), B1 plan by default
- Storage: one private Storage account with a container per web app (`mdca-files`, `mdca-files-saml`)
- Infrastructure: resource-group-scoped Bicep (`infra/main.bicep` plus the `infra/web-app.bicep` module)

## Architecture
- `server.js` – routes, sessions, upload/download
- `storage.js` – Blob Storage (managed identity) or local-folder fallback
- `auth/` – `index.js` selects the provider; `oidc.js` and `saml.js` register Passport strategies
- `infra/main.bicep` – plan, VNet, Blob private endpoint and DNS, Storage account and containers (shared resources only)
- `infra/web-app.bicep` – standalone template deployed once per provider; App Service on the existing plan/subnet with system-assigned identity and `Storage Blob Data Contributor` on the storage account
- `scripts/deploy-oidc.ps1`, `scripts/deploy-saml.ps1` – per-provider provisioning, Entra setup (OIDC automated; SAML two-run), app settings via JSON file, code deploy, `/health` verification; shared helpers in `scripts/common.ps1`
- `scripts/deploy.ps1` – packages the app with `tar` and runs `az webapp deploy`
- App settings are set by `az webapp config appsettings set`, not Bicep, because an ARM deployment replaces all app settings
- Health endpoint: `/health`

## Deployment guidance
See `docs/oidc-setup.md` and `docs/saml-setup.md`.

## Validation checks
- [x] `node --check` for server, storage, and auth modules
- [x] EJS template compilation
- [x] `az bicep build --file .\infra\main.bicep` (no warnings)
- [x] Local server smoke tests for OIDC and SAML, configured and unconfigured
- [x] OIDC discovery against Entra's public metadata; SAML login redirect generation
- [ ] `az deployment group what-if` / deployment against a real subscription (not run)
- [x] Unset `AUTH_PROVIDER` in Azure is reported, not defaulted\n- [ ] Deployment scripts against a real subscription and tenant (not run)\n- [ ] End-to-end Entra OIDC and SAML sign-in (requires a tenant)
