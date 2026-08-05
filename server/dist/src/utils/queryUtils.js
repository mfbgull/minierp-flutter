"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getQueryParam = getQueryParam;
exports.getRouteParam = getRouteParam;
exports.getQueryNumber = getQueryNumber;
exports.getQueryInteger = getQueryInteger;
/**
 * Safely extracts a string value from a query parameter that might be a string, array of strings, or ParsedQs
 * @param param The query parameter value (could be string, string[], or ParsedQs)
 * @returns The string value or undefined if not present
 */
function getQueryParam(param) {
    if (Array.isArray(param)) {
        const firstElement = param[0];
        if (typeof firstElement === 'string') {
            return firstElement;
        }
        else if (typeof firstElement === 'object' && firstElement !== null) {
            return JSON.stringify(firstElement);
        }
        return String(firstElement);
    }
    else if (typeof param === 'object' && param !== null) {
        // Handle ParsedQs object - convert to string
        return JSON.stringify(param);
    }
    return param;
}
/**
 * Safely extracts a string value from a route parameter that might be a string or array of strings
 * @param param The route parameter value (could be string or string[])
 * @returns The string value
 */
function getRouteParam(param) {
    if (Array.isArray(param)) {
        return param[0] || '';
    }
    return param;
}
/**
 * Safely extracts a numeric value from a query parameter
 * @param param The query parameter value (could be string, string[], or ParsedQs)
 * @param defaultValue Default value if parameter is not present or invalid
 * @returns The parsed number or default value
 */
function getQueryNumber(param, defaultValue = NaN) {
    const strValue = getQueryParam(param);
    if (strValue === undefined) {
        return defaultValue;
    }
    const numValue = Number(strValue);
    return isNaN(numValue) ? defaultValue : numValue;
}
/**
 * Safely extracts an integer value from a query parameter
 * @param param The query parameter value (could be string, string[], or ParsedQs)
 * @param defaultValue Default value if parameter is not present or invalid
 * @returns The parsed integer or default value
 */
function getQueryInteger(param, defaultValue = NaN) {
    const strValue = getQueryParam(param);
    if (strValue === undefined) {
        return defaultValue;
    }
    const numValue = parseInt(strValue, 10);
    return isNaN(numValue) ? defaultValue : numValue;
}
//# sourceMappingURL=queryUtils.js.map