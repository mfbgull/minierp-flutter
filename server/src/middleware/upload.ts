import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { resolveUploadsDir } from '../utils/serverRoot';

// Ensure upload directories exist
const uploadDir = resolveUploadsDir();
const employeeDocsDir = path.join(uploadDir, 'employees');

if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
if (!fs.existsSync(employeeDocsDir)) fs.mkdirSync(employeeDocsDir, { recursive: true });

// Allowed document types and the file extensions each may carry. The declared
// MIME type is client-controlled, so it is only accepted together with a
// matching extension.
const MIME_EXTENSIONS: Record<string, string[]> = {
  'application/pdf': ['.pdf'],
  'image/jpeg': ['.jpg', '.jpeg'],
  'image/png': ['.png'],
  'image/gif': ['.gif'],
  'application/msword': ['.doc'],
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ['.docx'],
  'application/vnd.ms-excel': ['.xls'],
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ['.xlsx'],
  'text/plain': ['.txt'],
};

// Configure storage for employee documents
const employeeStorage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    cb(null, employeeDocsDir);
  },
  filename: (_req, file, cb) => {
    const uniqueSuffix = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    // The stored extension comes from the validated MIME type, never from the
    // client-supplied file name (FILE-002).
    const ext = MIME_EXTENSIONS[file.mimetype]?.[0] ?? '';
    cb(null, `doc-${uniqueSuffix}${ext}`);
  }
});

// File filter - allow common document types
const documentFilter = (_req: Express.Request, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
  const allowedExtensions = MIME_EXTENSIONS[file.mimetype];
  if (!allowedExtensions) {
    cb(new Error(`File type ${file.mimetype} is not allowed`));
    return;
  }
  const ext = path.extname(file.originalname).toLowerCase();
  if (!allowedExtensions.includes(ext)) {
    cb(new Error(`File extension "${ext || '(none)'}" does not match type ${file.mimetype}`));
    return;
  }
  cb(null, true);
};

export const uploadEmployeeDoc = multer({
  storage: employeeStorage,
  fileFilter: documentFilter,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB max
  }
});

export { employeeDocsDir };
