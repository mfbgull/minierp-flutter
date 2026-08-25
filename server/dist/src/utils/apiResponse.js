"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendSuccess = sendSuccess;
exports.sendCreated = sendCreated;
exports.sendBadRequest = sendBadRequest;
exports.sendUnauthorized = sendUnauthorized;
exports.sendForbidden = sendForbidden;
exports.sendNotFound = sendNotFound;
exports.sendConflict = sendConflict;
exports.sendInternalError = sendInternalError;
function sendSuccess(res, data, statusCode = 200, meta) {
    const response = { success: true, data };
    if (meta)
        response.meta = meta;
    res.status(statusCode).json(response);
}
function sendCreated(res, data) {
    sendSuccess(res, data, 201);
}
function sendError(res, statusCode, code, message, details) {
    const response = {
        success: false,
        error: { code, message },
    };
    if (details)
        response.error.details = details;
    res.status(statusCode).json(response);
}
function sendBadRequest(res, message = 'Bad request') {
    sendError(res, 400, 'INVALID_INPUT', message);
}
function sendUnauthorized(res, message = 'Unauthorized') {
    sendError(res, 401, 'UNAUTHORIZED', message);
}
function sendForbidden(res, message = 'Forbidden') {
    sendError(res, 403, 'FORBIDDEN', message);
}
function sendNotFound(res, resource = 'Resource') {
    sendError(res, 404, 'RESOURCE_NOT_FOUND', `${resource} not found`);
}
function sendConflict(res, message = 'Resource already exists') {
    sendError(res, 409, 'RESOURCE_ALREADY_EXISTS', message);
}
function sendInternalError(res, message = 'Internal server error') {
    sendError(res, 500, 'INTERNAL_SERVER_ERROR', message);
}
