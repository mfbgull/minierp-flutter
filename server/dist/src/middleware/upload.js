"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.employeeDocsDir = exports.uploadEmployeeDoc = void 0;
const multer_1 = __importDefault(require("multer"));
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
// Ensure upload directories exist
const uploadDir = path_1.default.join(__dirname, '../../uploads');
const employeeDocsDir = path_1.default.join(uploadDir, 'employees');
exports.employeeDocsDir = employeeDocsDir;
if (!fs_1.default.existsSync(uploadDir))
    fs_1.default.mkdirSync(uploadDir, { recursive: true });
if (!fs_1.default.existsSync(employeeDocsDir))
    fs_1.default.mkdirSync(employeeDocsDir, { recursive: true });
// Configure storage for employee documents
const employeeStorage = multer_1.default.diskStorage({
    destination: (_req, _file, cb) => {
        cb(null, employeeDocsDir);
    },
    filename: (_req, file, cb) => {
        const uniqueSuffix = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
        const ext = path_1.default.extname(file.originalname);
        cb(null, `doc-${uniqueSuffix}${ext}`);
    }
});
// File filter - allow common document types
const documentFilter = (_req, file, cb) => {
    const allowedMimes = [
        'application/pdf',
        'image/jpeg',
        'image/png',
        'image/gif',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'text/plain',
    ];
    if (allowedMimes.includes(file.mimetype)) {
        cb(null, true);
    }
    else {
        cb(new Error(`File type ${file.mimetype} is not allowed`));
    }
};
exports.uploadEmployeeDoc = (0, multer_1.default)({
    storage: employeeStorage,
    fileFilter: documentFilter,
    limits: {
        fileSize: 10 * 1024 * 1024, // 10MB max
    }
});
//# sourceMappingURL=upload.js.map