const { Strategy: SamlStrategy } = require('@node-saml/passport-saml');

const CLAIMS = {
  email: [
    'email',
    'mail',
    'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
    'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn',
  ],
  name: [
    'displayName',
    'http://schemas.microsoft.com/identity/claims/displayname',
    'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name',
  ],
  groups: ['groups', 'http://schemas.microsoft.com/ws/2008/06/identity/claims/groups'],
};

const pick = (profile, keys) => keys.map((key) => profile[key]).find(Boolean);

module.exports = async function configureSaml(passport, port) {
  const { SAML_ENTRY_POINT: entryPoint, SAML_ISSUER: issuer, SAML_IDP_CERT: idpCert } = process.env;

  if (!entryPoint || !issuer || !idpCert) {
    return 'SAML is not configured. Add the Entra SAML settings to enable sign-in.';
  }

  passport.use(
    'saml',
    new SamlStrategy(
      {
        callbackUrl: process.env.SAML_CALLBACK_URL || `http://localhost:${port}/auth/callback`,
        entryPoint,
        issuer,
        idpCert,
        // Entra signs the assertion by default, not the outer response.
        wantAssertionsSigned: true,
        wantAuthnResponseSigned: false,
      },
      (profile, done) => {
        const email = pick(profile, CLAIMS.email) || '';
        const groups = pick(profile, CLAIMS.groups) || [];

        done(null, {
          id: profile.nameID || email || 'unknown-user',
          name: pick(profile, CLAIMS.name) || email || 'User',
          email,
          groups: [].concat(groups),
          issuer: profile.issuer || entryPoint,
        });
      }
    )
  );

  return null;
};
