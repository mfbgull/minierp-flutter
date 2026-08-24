"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const searchService_1 = require("../services/searchService");
function getSearch(req, res) {
    try {
        const q = req.query.q?.trim() ?? '';
        const limit = Math.min(Number(req.query.limit ?? 10), 10); // spec: max 10 per entity
        if (!q || q.length < 2) {
            res.status(400).json({
                success: false,
                error: 'Query must be at least 2 characters',
            });
            return;
        }
        const userId = req.user?.id ?? 0;
        const results = (0, searchService_1.search)(q, limit, userId);
        res.status(200).json({
            success: true,
            data: {
                query: q,
                results: results.results,
                total: results.total,
            },
        });
    }
    catch {
        res.status(500).json({
            success: false,
            error: 'Search failed',
        });
    }
}
exports.default = {
    getSearch,
};
//# sourceMappingURL=searchController.js.map