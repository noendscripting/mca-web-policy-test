require('dotenv').config();
const path = require('path');
const { pipeline } = require('stream');
const express = require('express');
const session = require('express-session');
const passport = require('passport');
const multer = require('multer');
const { configureAuth } = require('./auth');
const { createStorage } = require('./storage');

const app = express();
const PORT = Number(process.env.PORT || 3000);
const upload = multer({ storage: multer.memoryStorage() });
let storage;

app.set('views', path.join(__dirname, 'views'));
app.set('view engine', 'ejs');
app.locals.pageTitle = 'MCA Web Policy Test';

app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
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

// Express 4 does not catch rejected promises from async handlers.
const wrap = (handler) => (req, res, next) => handler(req, res, next).catch(next);

function ensureAuthenticated(req, res, next) {
  return req.isAuthenticated() ? next() : res.redirect('/');
}

function authenticate(options) {
  return (req, res, next) => {
    const { auth } = app.locals;
    return auth.enabled ? passport.authenticate(auth.protocol, options)(req, res, next) : res.redirect('/');
  };
}

function render(req, res, files, status = 200) {
  return res.status(status).render('index', { user: req.user || null, files });
}

app.get('/health', (req, res) => res.json({
  status: 'ok',
  storage: app.locals.storageMode,
  authProvider: app.locals.auth.protocol,
  authEnabled: app.locals.auth.enabled,
}));

app.get('/', wrap(async (req, res) => render(req, res, await storage.list())));

app.get('/auth/login', authenticate());

// OIDC redirects back with GET; SAML posts the assertion.
app.all('/auth/callback', authenticate({ successRedirect: '/', failWithError: true }));

app.get('/auth/logout', (req, res, next) => {
  req.logout((error) => {
    if (error) {
      return next(error);
    }

    req.session.destroy(() => res.redirect('/'));
  });
});

app.post('/upload', ensureAuthenticated, upload.single('file'), wrap(async (req, res) => {
  if (req.file) {
    const uploaded = await storage.save(req.file);
    console.log(`Uploaded ${uploaded.displayName} (${uploaded.storage})`);
  }

  res.redirect('/');
}));

app.get('/download/:name', ensureAuthenticated, wrap(async (req, res) => {
  const file = await storage.download(req.params.name);
  if (!file) {
    return res.status(404).send('File not found.');
  }

  res.attachment(file.displayName);
  res.type(file.contentType);
  pipeline(file.stream, res, (error) => {
    if (error) {
      console.error('Download failed:', error.message);
    }
  });
}));

app.use((req, res) => render(req, res, [], 404));

app.use((error, req, res, next) => {
  console.error(`${req.method} ${req.path} failed:`, error.message);
  if (res.headersSent) {
    return next(error);
  }

  return req.path === '/auth/callback' ? res.redirect('/') : res.status(500).send('Something went wrong.');
});

(async () => {
  storage = await createStorage();
  app.locals.storageMode = storage.mode;
  app.locals.auth = await configureAuth(passport, PORT);
  app.listen(PORT, () => console.log(`MCA web policy tester listening on http://localhost:${PORT}`));
})().catch((error) => {
  console.error('Application failed to initialize:', error);
  process.exit(1);
});
