const fs = require('fs');
const path = require('path');
const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');

const LOCAL_DIR = path.join(__dirname, 'uploads');
const DEFAULT_CONTENT_TYPE = 'application/octet-stream';

const displayName = (fileName) => fileName.replace(/^\d+-/, '');
const uniqueName = (original) => `${Date.now()}-${(original || 'file').replace(/[\\/:*?"<>|]/g, '-')}`;
const newestFirst = (a, b) => new Date(b.createdAt) - new Date(a.createdAt);

function toEntry(mode, fileName, size, createdAt) {
  return {
    fileName,
    displayName: displayName(fileName),
    size,
    createdAt: new Date(createdAt || Date.now()).toISOString(),
    storage: mode,
  };
}

async function createBlobStorage(connectionString, accountName) {
  const service = connectionString
    ? BlobServiceClient.fromConnectionString(connectionString)
    : new BlobServiceClient(`https://${accountName}.blob.core.windows.net`, new DefaultAzureCredential());
  const container = service.getContainerClient(process.env.AZURE_STORAGE_CONTAINER_NAME || 'mdca-files');
  await container.createIfNotExists();

  return {
    mode: 'blob',

    async list() {
      const entries = [];
      for await (const blob of container.listBlobsFlat()) {
        entries.push(toEntry('blob', blob.name, blob.properties.contentLength, blob.properties.createdOn));
      }
      return entries.sort(newestFirst);
    },

    async save(file) {
      const fileName = uniqueName(file.originalname);
      await container.getBlockBlobClient(fileName).uploadData(file.buffer, {
        blobHTTPHeaders: { blobContentType: file.mimetype || DEFAULT_CONTENT_TYPE },
      });
      return toEntry('blob', fileName, file.size);
    },

    async download(fileName) {
      try {
        const response = await container.getBlobClient(fileName).download();
        return {
          stream: response.readableStreamBody,
          contentType: response.contentType || DEFAULT_CONTENT_TYPE,
          displayName: displayName(fileName),
        };
      } catch (error) {
        if (error.statusCode === 404) {
          return null;
        }
        throw error;
      }
    },
  };
}

function createLocalStorage() {
  fs.mkdirSync(LOCAL_DIR, { recursive: true });

  return {
    mode: 'local',

    async list() {
      const names = await fs.promises.readdir(LOCAL_DIR);
      const entries = await Promise.all(
        names.map(async (name) => {
          const stats = await fs.promises.stat(path.join(LOCAL_DIR, name));
          return stats.isFile() ? toEntry('local', name, stats.size, stats.mtime) : null;
        })
      );
      return entries.filter(Boolean).sort(newestFirst);
    },

    async save(file) {
      const fileName = uniqueName(file.originalname);
      await fs.promises.writeFile(path.join(LOCAL_DIR, fileName), file.buffer);
      return toEntry('local', fileName, file.size);
    },

    async download(fileName) {
      // basename prevents path traversal outside the uploads directory
      const safeName = path.basename(fileName);
      const filePath = path.join(LOCAL_DIR, safeName);
      if (!(await fs.promises.stat(filePath).then((s) => s.isFile(), () => false))) {
        return null;
      }
      return {
        stream: fs.createReadStream(filePath),
        contentType: DEFAULT_CONTENT_TYPE,
        displayName: displayName(safeName),
      };
    },
  };
}

// Uses Blob Storage when configured, otherwise a local folder for development.
async function createStorage() {
  const connectionString = process.env.AZURE_STORAGE_CONNECTION_STRING;
  const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
  return connectionString || accountName
    ? createBlobStorage(connectionString, accountName)
    : createLocalStorage();
}

module.exports = { createStorage };
