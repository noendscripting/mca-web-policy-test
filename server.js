const path = require('path');
const fs = require('fs');
const express = require('express');
const session = require('express-session');
const passport = require('passport');
const multer = require('multer');
const { Issuer, Strategy } = require('openid-client');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');
require('dotenv').config();

const app = express();
const PORT = Number(process.env.PORT || 3000);
const LOCAL_UPLOAD_DIR = path.join(__dirname, 'uploads');
const appRoot = __dirname;

app.set('views', path.join(appRoot, 'views'));
app.set('view engine', 'ejs');
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(appRoot, 'public')));
app.use(
  session({
    secret: process.env.SESSION_SECRET || 'change-me-in-production',
    resave: false,
    saveUninitialized: false,
    cookie: { secure: false, sameSite: 'lax' },
  })
);
app.use(passport.initialize());
app.use(passport.session());

passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((user, done) => done(null, user));

const upload = multer({ storage: multer.memoryStorage() });

function makeSafeFileName(name) {
  return (name || 'file').replace(/[\\/:*?"<>|]/g, '-');
}

async function readLocalFiles() {
  fs.mkdirSync(LOCAL_UPLOAD_DIR, { recursive: true });
  return fs.readdirSync(LOCAL_UPLOAD_DIR, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => {
      const filePath = path.join(LOCAL_UPLOAD_DIR, entry.name);
      const stats = fs.statSync(filePath);
      const displayName = entry.name.replace(/^\d+-/, '');
      return {
        fileName: entry.name,
        displayName,
        size: stats.size,
        createdAt: new Date(stats.mtime).toISOString(),
        storage: 'local',
      };
    })
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
}

async function getBlobContainerClient() {
  const connectionString = process.env.AZURE_STORAGE_CONNECTION_STRING;
  const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
  const containerName = process.env.AZURE_STORAGE_CONTAINER_NAME || 'mdca-files';

  if (connectionString) {
    const client = BlobServiceClient.fromConnectionString(connectionString);
    return { client, containerName, mode: 'blob' };
  }

  if (accountName) {
    const client = new BlobServiceClient(
      `https://${accountName}.blob.core.windows.net`,
      new DefaultAzureCredential()
    );
    return { client, containerName, mode: 'blob' };
  }

  return null;
}

async function ensureStorage() {
  const blobConfig = await getBlobContainerClient();
  if (blobConfig) {
    const containerClient = blobConfig.client.getContainerClient(blobConfig.containerName);
    await containerClient.createIfNotExists({ access: 'blob' });
    return { mode: 'blob', containerClient, containerName: blobConfig.containerName };
  }

  fs.mkdirSync(LOCAL_UPLOAD_DIR, { recursive: true });
  return { mode: 'local', containerName: 'local' };
}

async function listFiles() {
  const storage = await ensureStorage();

  if (storage.mode === 'blob') {
    const entries = [];
    for await (const item of storage.containerClient.listBlobsFlat()) {
      entries.push({
        fileName: item.name,
        displayName: item.name.replace(/^\d+-/, ''),
        size: item.properties.contentLength,
        createdAt: new Date(item.properties.creationTime || Date.now()).toISOString(),
        storage: 'blob',
      });
    }
    return entries.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  return readLocalFiles();
}

async function recordFileUpload(file) {
  const storage = await ensureStorage();
  const safeName = makeSafeFileName(file.originalname);
  const uniqueName = `${Date.now()}-${safeName}`;

  if (storage.mode === 'blob') {
    const blobClient = storage.containerClient.getBlockBlobClient(uniqueName);
    await blobClient.uploadData(file.buffer, {
      blobHTTPHeaders: {
        blobContentType: file.mimetype || 'application/octet-stream',
      },
    });

    return {
      fileName: uniqueName,
      displayName: safeName,
      size: file.size,
      createdAt: new Date().toISOString(),
      storage: 'blob',
    };
  }

  const destinationPath = path.join(LOCAL_UPLOAD_DIR, uniqueName);
  fs.writeFileSync(destinationPath, file.buffer);
  return {
    fileName: uniqueName,
    displayName: safeName,
    size: file.size,
    createdAt: new Date().toISOString(),
    storage: 'local',
  };
}

async function resolveFileForDownload(fileName) {
  const storage = await ensureStorage();

  if (storage.mode === 'blob') {
    const client = storage.containerClient.getBlobClient(fileName);
    const exists = await client.exists();
    if (!exists) {
      throw new Error('File not found in storage');
    }

    const properties = await client.getProperties();
    const displayName = fileName.replace(/^\d+-/, '');
    return {
      blobClient: client,
      fileName,
      displayName,
      contentType: properties.contentSettings.contentType || 'application/octet-stream',
      storage: 'blob',
    };
  }

  const localPath = path.join(LOCAL_UPLOAD_DIR, fileName);
  if (!fs.existsSync(localPath)) {
    throw new Error('File not found in local storage');
  }

  return {
    localPath,
    fileName,
    displayName: fileName.replace(/^\d+-/, ''),
    contentType: 'application/octet-stream',
    storage: 'local',
  };
}

app.locals.oidcEnabled = false;
app.locals.oidcMessage = 'OIDC is not configured yet. Add Entra values in .env to enable sign-in.';
app.locals.storageMode = 'local';

async function initializeOidc() {
  const tenantId = process.env.AAD_TENANT_ID;
  const clientId = process.env.AAD_CLIENT_ID;
  const clientSecret = process.env.AAD_CLIENT_SECRET;
  const redirectUri = process.env.OIDC_REDIRECT_URI || `http://localhost:${PORT}/auth/callback`;
  const issuerUrl = process.env.OIDC_ISSUER || (tenantId ? `https://login.microsoftonline.com/${tenantId}/v2.0` : null);

  if (!issuerUrl || !clientId || !clientSecret) {
    return;
  }

  try {
    const issuer = await Issuer.discover(issuerUrl);
    const client = new issuer.Client({
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uris: [redirectUri],
      response_types: ['code'],
      token_endpoint_auth_method: 'client_secret_post',
    });

    passport.use(
      'oidc',
      new Strategy({ client, params: { scope: 'openid profile email' } }, (tokenset, userinfo, done) => {
        const user = {
          id: userinfo.sub || userinfo.email || 'unknown-user',
          name: userinfo.name || userinfo.preferred_username || 'User',
          email: userinfo.email || userinfo.preferred_username || '',
          groups: userinfo.groups || [],
          accessToken: tokenset.access_token,
          idToken: tokenset.id_token,
        };

        return done(null, user);
      })
    );

    app.locals.oidcEnabled = true;
    app.locals.oidcMessage = null;
  } catch (error) {
    console.error('OIDC configuration failed:', error.message);
    app.locals.oidcEnabled = false;
    app.locals.oidcMessage = 'OIDC discovery failed. Check the Entra OIDC values in .env.';
  }
}

async function boot() {
  const storage = await ensureStorage();
  app.locals.storageMode = storage.mode;
  await initializeOidc();
}

function ensureAuthenticated(req, res, next) {
  if (req.isAuthenticated && req.isAuthenticated()) {
    return next();
  }

  return res.redirect('/');
}

app.get('/health', (req, res) => res.json({ status: 'ok', storage: app.locals.storageMode, oidcEnabled: app.locals.oidcEnabled }));

app.get('/', async (req, res) => {
  const files = await listFiles();
  res.render('index', {
    pageTitle: 'MCA Web Policy Test',
    user: req.user || null,
    files,
    oidcEnabled: app.locals.oidcEnabled,
    configWarning: app.locals.oidcMessage,
    storageMode: app.locals.storageMode,
  });
});

app.get('/auth/login', (req, res, next) => {
  if (!app.locals.oidcEnabled) {
    return res.redirect('/');
  }

  return passport.authenticate('oidc')(req, res, next);
});

app.get('/auth/callback', (req, res, next) => {
  passport.authenticate('oidc', {
    successRedirect: '/',
    failureRedirect: '/',
  })(req, res, next);
});

app.get('/auth/logout', (req, res, next) => {
  req.logout((error) => {
    if (error) {
      return next(error);
    }

    req.session.destroy(() => res.redirect('/'));
  });
});

app.post('/upload', ensureAuthenticated, upload.single('file'), async (req, res) => {
  if (!req.file) {
    return res.redirect('/');
  }

  const uploaded = await recordFileUpload(req.file);
  console.log(`Uploaded ${uploaded.displayName} (${uploaded.storage})`);
  return res.redirect('/');
});

app.get('/download/:name', ensureAuthenticated, async (req, res) => {
  try {
    const file = await resolveFileForDownload(req.params.name);
    if (file.storage === 'blob') {
      const stream = await file.blobClient.download();
      const buffer = await new Promise((resolve, reject) => {
        const chunks = [];
        stream.readableStreamBody.on('data', (chunk) => chunks.push(chunk));
        stream.readableStreamBody.on('end', () => resolve(Buffer.concat(chunks)));
        stream.readableStreamBody.on('error', reject);
      });

      res.setHeader('Content-Type', file.contentType);
      res.setHeader('Content-Disposition', `attachment; filename="${file.displayName}"`);
      return res.send(buffer);
    }

    res.setHeader('Content-Type', file.contentType);
    res.setHeader('Content-Disposition', `attachment; filename="${file.displayName}"`);
    return res.download(file.localPath, file.displayName);
  } catch (error) {
    console.error('Download failed:', error.message);
    return res.status(404).send('File not found.');
  }
});

app.use((req, res) => {
  res.status(404).render('index', {
    pageTitle: 'MCA Web Policy Test',
    user: req.user || null,
    files: [],
    oidcEnabled: app.locals.oidcEnabled,
    configWarning: app.locals.oidcMessage,
    storageMode: app.locals.storageMode,
  });
});

boot()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`MCA web policy tester listening on http://localhost:${PORT}`);
    });
  })
  .catch((error) => {
    console.error('Application failed to initialize:', error);
    process.exit(1);
  });
