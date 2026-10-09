const OpenIDConnectStrategy = require('passport-openidconnect').Strategy;

module.exports = async function configureOidc(passport, port) {
  const { AAD_TENANT_ID: tenantId, AAD_CLIENT_ID: clientId, AAD_CLIENT_SECRET: clientSecret } = process.env;
  const issuer = process.env.OIDC_ISSUER || (tenantId && `https://login.microsoftonline.com/${tenantId}/v2.0`);

  if (!issuer || !clientId || !clientSecret) {
    return 'OIDC is not configured. Add the Entra OIDC settings to enable sign-in.';
  }

  const response = await fetch(`${issuer.replace(/\/$/, '')}/.well-known/openid-configuration`);
  if (!response.ok) {
    throw new Error(`OIDC discovery returned HTTP ${response.status}`);
  }
  const metadata = await response.json();

  passport.use(
    'oidc',
    new OpenIDConnectStrategy(
      {
        issuer,
        authorizationURL: metadata.authorization_endpoint,
        tokenURL: metadata.token_endpoint,
        userInfoURL: metadata.userinfo_endpoint,
        clientID: clientId,
        clientSecret,
        callbackURL: process.env.OIDC_REDIRECT_URI || `http://localhost:${port}/auth/callback`,
        scope: process.env.OIDC_SCOPES || `openid profile email api://${clientId}/access_as_user`,
      },
      (issuerClaim, profile, done) => done(null, {
        id: profile.id || 'unknown-user',
        name: profile.displayName || profile.username || 'User',
        email: profile.emails && profile.emails[0] ? profile.emails[0].value : '',
        groups: profile._json && Array.isArray(profile._json.groups) ? profile._json.groups : [],
        issuer: issuerClaim,
      })
    )
  );

  return null;
};
