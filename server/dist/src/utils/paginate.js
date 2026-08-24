"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MAX_PAGE_SIZE = exports.DEFAULT_PAGE_SIZE = void 0;
exports.parsePageParams = parsePageParams;
exports.envelope = envelope;
const queryUtils_1 = require("./queryUtils");
exports.DEFAULT_PAGE_SIZE = 100;
exports.MAX_PAGE_SIZE = 500;
function parsePageParams(req) {
    const page = Math.max(1, (0, queryUtils_1.getQueryInteger)(req.query.page, 1) || 1);
    const rawLimit = (0, queryUtils_1.getQueryInteger)(req.query.limit, exports.DEFAULT_PAGE_SIZE) || exports.DEFAULT_PAGE_SIZE;
    const limit = Math.min(Math.max(1, rawLimit), exports.MAX_PAGE_SIZE);
    return { page, limit, offset: (page - 1) * limit };
}
function envelope(total, p) {
    return {
        page: p.page,
        limit: p.limit,
        total,
        total_pages: Math.max(1, Math.ceil(total / p.limit)),
    };
}
//# sourceMappingURL=paginate.js.map