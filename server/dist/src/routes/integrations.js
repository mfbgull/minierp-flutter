"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const requirePermission_1 = require("../middleware/requirePermission");
const settingsController_1 = __importDefault(require("../controllers/settingsController"));
const logger_1 = __importDefault(require("../utils/logger"));
const router = (0, express_1.Router)();
router.use(auth_1.authenticateToken);
router.use((0, requirePermission_1.requirePermission)('integrations', 'read'));
router.get('/settings', (0, requirePermission_1.requirePermission)('integrations', 'read'), (_req, res) => {
    try {
        const integrationSettings = settingsController_1.default.getIntegrationSettings();
        res.json(integrationSettings);
    }
    catch (error) {
        logger_1.default.error('Get integration settings error:', error);
        res.status(500).json({ error: 'Failed to fetch integration settings' });
    }
});
router.put('/settings/:service', (0, requirePermission_1.requirePermission)('integrations', 'update'), (req, res) => {
    try {
        const { service } = req.params;
        const serviceKey = typeof service === 'string' ? service : service[0];
        settingsController_1.default.updateIntegrationSettings(serviceKey, req.body);
        res.json({ success: true, message: 'Settings updated successfully' });
    }
    catch (error) {
        logger_1.default.error('Update integration settings error:', error);
        if (error instanceof Error && error.message === 'Invalid service name') {
            res.status(400).json({ error: 'Invalid service name' });
        }
        else {
            res.status(500).json({ error: 'Failed to update integration settings' });
        }
    }
});
exports.default = router;
