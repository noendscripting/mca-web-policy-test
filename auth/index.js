const providers = {
  oidc: { displayName: 'Microsoft Entra ID (OIDC)', configure: require('./oidc') },
  saml: { displayName: 'Microsoft Entra ID (SAML)', configure: require('./saml') },
};

// Each provider's configure() registers its Passport strategy and returns a
// message when required settings are missing, or null when ready.
async function configureAuth(passport, port) {
  // Locally AUTH_PROVIDER defaults to oidc. In Azure it must be set explicitly, so a
  // missing value is reported instead of silently showing the wrong provider.
  if (!process.env.AUTH_PROVIDER && process.env.WEBSITE_SITE_NAME) {
    return {
      protocol: 'unset',
      displayName: 'Microsoft Entra ID',
      enabled: false,
      message: 'AUTH_PROVIDER is not set on this App Service. Run the OIDC or SAML deployment script.',
    };
  }

  const protocol = (process.env.AUTH_PROVIDER || 'oidc').toLowerCase();
  const provider = providers[protocol];
  if (!provider) {
    throw new Error(`Unsupported AUTH_PROVIDER "${protocol}". Expected "oidc" or "saml".`);
  }

  let message;
  try {
    message = await provider.configure(passport, port);
  } catch (error) {
    console.error(`${protocol.toUpperCase()} configuration failed:`, error.message);
    message = `${protocol.toUpperCase()} initialization failed. Check the settings and server logs.`;
  }

  return { protocol, displayName: provider.displayName, enabled: !message, message };
}

module.exports = { configureAuth };
