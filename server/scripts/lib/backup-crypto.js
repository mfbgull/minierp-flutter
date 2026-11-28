'use strict';

/**
 * Backup encryption at rest (audit D29, option B — database copy only).
 *
 * A backup file is a second full copy of the books, so it is wrapped in an
 * encrypted container after its integrity check. The container is a small
 * self-describing file:
 *
 *   magic 'ERPENC01' (8) | salt (16) | iv (12) | ciphertext | tag (16)
 *
 * The key comes from `BACKUP_ENCRYPTION_KEY` and is stretched with scrypt
 * using a fresh random salt per file, so two backups of the same content
 * never produce the same bytes. AES-256-GCM authenticates as it decrypts: a
 * wrong passphrase or a tampered file fails at `final()` instead of
 * producing a corrupt database.
 *
 * Reading and writing are synchronous and chunked, because `runBackup()` is
 * synchronous and a database copy must not be held in memory whole.
 *
 * This module is plain CommonJS on purpose: the operator scripts under
 * `scripts/` run with plain `node`, and they must use exactly the same
 * format as the server.
 */
const crypto = require('crypto');
const fs = require('fs');

const ALGORITHM = 'aes-256-gcm';
const MAGIC = 'ERPENC01';
const MAGIC_BUFFER = Buffer.from(MAGIC, 'ascii');
const SALT_LENGTH = 16;
const IV_LENGTH = 12;
const TAG_LENGTH = 16;
const HEADER_LENGTH = MAGIC_BUFFER.length + SALT_LENGTH + IV_LENGTH;
const KEY_LENGTH = 32;
const CHUNK_SIZE = 1024 * 1024;
// scrypt at N=32768 needs 128*N*r = 32 MiB, which is exactly Node's default
// maxmem. Ask for headroom instead of sitting on the limit.
const SCRYPT_OPTIONS = { N: 32768, r: 8, p: 1, maxmem: 96 * 1024 * 1024 };

/** The configured backup passphrase, or null when none is set. */
function backupPassphrase() {
  const value = process.env.BACKUP_ENCRYPTION_KEY;
  return value && value.trim() ? value : null;
}

/** True for a generated backup name that carries an encrypted container. */
function isEncryptedName(name) {
  return typeof name === 'string' && name.endsWith('.db.enc');
}

/** True when the file on disk starts with this container's magic. */
function isEncryptedFileSync(filePath) {
  let fd = -1;
  try {
    fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(MAGIC_BUFFER.length);
    const read = fs.readSync(fd, buf, 0, buf.length, 0);
    return read === buf.length && buf.equals(MAGIC_BUFFER);
  } catch (err) {
    return false;
  } finally {
    closeQuietly(fd);
  }
}

function deriveKey(passphrase, salt) {
  return crypto.scryptSync(passphrase, salt, KEY_LENGTH, SCRYPT_OPTIONS);
}

/** writeSync may write fewer bytes than asked; loop until it is all out. */
function writeAll(fd, buffer) {
  let offset = 0;
  while (offset < buffer.length) {
    offset += fs.writeSync(fd, buffer, offset, buffer.length - offset);
  }
}

function closeQuietly(fd) {
  if (fd < 0) return;
  try {
    fs.closeSync(fd);
  } catch (err) {
    /* a handle that refuses to close must not mask the real error */
  }
}

/**
 * Writes `srcPath` to `destPath` as an encrypted container.
 *
 * Throws when no passphrase is configured, when the source cannot be read,
 * or when the destination cannot be written. A failure never leaves a
 * partial container behind — a half-written file that looks like a backup
 * is worse than no file at all.
 */
function encryptFileSync(srcPath, destPath, passphrase) {
  if (!passphrase) {
    throw new Error('BACKUP_ENCRYPTION_KEY is not set — refusing to write a plain backup');
  }
  const salt = crypto.randomBytes(SALT_LENGTH);
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, deriveKey(passphrase, salt), iv);
  const header = Buffer.concat([MAGIC_BUFFER, salt, iv]);

  let input = -1;
  let output = -1;
  try {
    output = fs.openSync(destPath, 'w', 0o600);
    input = fs.openSync(srcPath, 'r');
    fs.writeSync(output, header);

    const chunk = Buffer.allocUnsafe(CHUNK_SIZE);
    for (;;) {
      const read = fs.readSync(input, chunk, 0, CHUNK_SIZE, null);
      if (read === 0) break;
      writeAll(output, cipher.update(chunk.subarray(0, read)));
    }
    writeAll(output, cipher.final());
    fs.writeSync(output, cipher.getAuthTag());
  } catch (err) {
    closeQuietly(output);
    output = -1;
    closeQuietly(input);
    input = -1;
    try {
      fs.rmSync(destPath, { force: true });
    } catch (rmErr) {
      /* the original error matters more */
    }
    throw err;
  } finally {
    closeQuietly(input);
    closeQuietly(output);
  }
}

/**
 * Writes the plaintext database behind an encrypted container to `destPath`.
 *
 * Throws when the file is not a container, when the passphrase is wrong, or
 * when the file has been tampered with — GCM authenticates before the last
 * byte is released, so a bad key never yields a corrupt database. On any
 * failure `destPath` is removed.
 */
function decryptFileSync(srcPath, destPath, passphrase) {
  if (!passphrase) {
    throw new Error('BACKUP_ENCRYPTION_KEY is not set — cannot decrypt this backup');
  }
  const size = fs.statSync(srcPath).size;
  if (size < HEADER_LENGTH + TAG_LENGTH) {
    throw new Error(`${srcPath} is too small to be an encrypted backup`);
  }

  let input = -1;
  let output = -1;
  try {
    input = fs.openSync(srcPath, 'r');

    const header = Buffer.alloc(HEADER_LENGTH);
    fs.readSync(input, header, 0, HEADER_LENGTH, 0);
    if (!header.subarray(0, MAGIC_BUFFER.length).equals(MAGIC_BUFFER)) {
      throw new Error(`${srcPath} is not an encrypted backup`);
    }
    const salt = header.subarray(MAGIC_BUFFER.length, MAGIC_BUFFER.length + SALT_LENGTH);
    const iv = header.subarray(MAGIC_BUFFER.length + SALT_LENGTH);

    const tag = Buffer.alloc(TAG_LENGTH);
    fs.readSync(input, tag, 0, TAG_LENGTH, size - TAG_LENGTH);

    const decipher = crypto.createDecipheriv(ALGORITHM, deriveKey(passphrase, salt), iv);
    decipher.setAuthTag(tag);

    output = fs.openSync(destPath, 'w', 0o600);
    const chunk = Buffer.allocUnsafe(CHUNK_SIZE);
    // Ciphertext runs from the end of the header to the start of the tag.
    let offset = HEADER_LENGTH;
    const ciphertextEnd = size - TAG_LENGTH;
    while (offset < ciphertextEnd) {
      const want = Math.min(CHUNK_SIZE, ciphertextEnd - offset);
      const read = fs.readSync(input, chunk, 0, want, offset);
      if (read === 0) break;
      offset += read;
      writeAll(output, decipher.update(chunk.subarray(0, read)));
    }
    // Wrong key or tampered bytes throw here, before anything is trusted.
    writeAll(output, decipher.final());
  } catch (err) {
    closeQuietly(output);
    output = -1;
    closeQuietly(input);
    input = -1;
    try {
      fs.rmSync(destPath, { force: true });
    } catch (rmErr) {
      /* the original error matters more */
    }
    throw err;
  } finally {
    closeQuietly(input);
    closeQuietly(output);
  }
}

module.exports = {
  MAGIC,
  HEADER_LENGTH,
  backupPassphrase,
  isEncryptedName,
  isEncryptedFileSync,
  encryptFileSync,
  decryptFileSync,
};
