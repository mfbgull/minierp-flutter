"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const router = express_1.default.Router();
const searchController_1 = __importDefault(require("../controllers/searchController"));
const auth_1 = require("../middleware/auth");
const validation_1 = require("../middleware/validation");
const zod_1 = require("zod");
const searchQuerySchema = zod_1.z.object({
    q: zod_1.z.string().min(2).max(100),
    limit: zod_1.z.coerce.number().int().min(1).max(10).optional().default(10),
});
router.use(auth_1.authenticateToken);
router.get('/', (0, validation_1.validateZodQuery)(searchQuerySchema), searchController_1.default.getSearch);
exports.default = router;
//# sourceMappingURL=search.js.map