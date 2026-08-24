"use strict";
/**
 * Report Query Engine
 * Translates a report config JSON into a SQL query and executes it.
 *
 * Accepts a config (same format stored in custom_reports.config) and
 * returns rows from the database with column names mapped to aliases.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.executeReport = executeReport;
const database_1 = __importDefault(require("../config/database"));
const entityRegistry_1 = require("./entityRegistry");
const logger_1 = __importDefault(require("../utils/logger"));
const expressionValidator_1 = require("./expressionValidator");
// ── Relative Date Resolution ─────────────────────────────────
const RELATIVE_DATE_TOKENS = {
    'today': "date('now')",
    'yesterday': "date('now', '-1 day')",
    'this_week': "date('now', 'weekday 1', '-7 days')",
    'this_month': "date('now', 'start of month')",
    'this_quarter': "date('now', 'start of month', '-' || ((cast(strftime('%m', 'now') as integer) - 1) % 3) || ' months')",
    'this_year': "date('now', 'start of year')",
    'last_7_days': "date('now', '-7 days')",
    'last_30_days': "date('now', '-30 days')",
    'last_90_days': "date('now', '-90 days')",
    'last_month_start': "date('now', 'start of month', '-1 month')",
    'last_month_end': "date('now', 'start of month', '-1 day')",
};
/**
 * Resolve a relative date token to a SQL expression string, or return null
 * if the value is not a relative date token (treat as literal value).
 */
function resolveRelativeDate(value) {
    if (RELATIVE_DATE_TOKENS[value]) {
        return RELATIVE_DATE_TOKENS[value];
    }
    const match = value.match(/^([+-]\d+)\s+(day|days|week|weeks|month|months|year|years)$/i);
    if (match) {
        const unit = match[2].toLowerCase();
        const sqlUnit = unit.endsWith('s') ? unit.slice(0, -1) : unit;
        return `date('now', '${match[1]} ${sqlUnit}')`;
    }
    return null;
}
/**
 * Check if a value is a relative date expression that should be inlined as SQL.
 * Returns { sqlExpr } if it should be inlined, or null to treat as a parameter value.
 */
function checkRelativeDate(value) {
    if (typeof value === 'string') {
        const sqlExpr = resolveRelativeDate(value);
        if (sqlExpr !== null) {
            return { sqlExpr };
        }
    }
    return null;
}
// ── Identifier Utilities ────────────────────────────────────
function quoteIdentifier(name) {
    return `"${name.replace(/"/g, '""')}"`;
}
/**
 * Build and execute a report query from a config.
 */
function executeReport(config) {
    const startTime = Date.now();
    // 1. Validate entity
    const entityDef = (0, entityRegistry_1.getEntity)(config.entity);
    if (!entityDef) {
        throw new Error(`Entity "${config.entity}" not found in registry`);
    }
    // REP-18 defense in depth: validate computed-column expressions against the
    // safe grammar BEFORE any SQL is built. Even if a controller misses this,
    // nothing unvalidated ever reaches query construction.
    const entityFieldNames = new Set(entityDef.fields.map(f => f.name));
    (0, expressionValidator_1.validateConfigExpressions)(config, entityFieldNames);
    const ctx = {
        validFieldNames: new Set(entityDef.fields.map(f => f.name)),
        primaryTableAlias: 'e',
        usedJoins: new Map(),
        joinClauses: [],
        paramValues: [],
    };
    // Add computed column names to valid field set
    if (config.computedColumns) {
        for (const cc of config.computedColumns) {
            ctx.validFieldNames.add(cc.name);
        }
    }
    const startIdx = ctx.paramValues.length;
    // 2. Build SELECT clause
    const selectItems = buildSelectClause(config, entityDef, ctx);
    // 3. Build FROM + JOINs
    const fromClause = buildFromClause(entityDef, ctx);
    // 4. Resolve needed joins based on referenced fields
    resolveNeededJoins(config, entityDef, ctx);
    // 5. Build WHERE clause
    const whereClause = buildWhereClause(config.filters, ctx);
    // 6. Build GROUP BY
    const groupByClause = buildGroupByClause(config, ctx);
    // 7. Build HAVING
    const havingClause = buildHavingClause(config, ctx);
    // 8. Build ORDER BY
    const orderByClause = buildOrderByClause(config.sort, config, ctx);
    // 9. Assemble SQL
    let sql = `SELECT ${selectItems.join(',\n  ')}\nFROM ${fromClause}`;
    if (ctx.joinClauses.length > 0) {
        sql += '\n' + ctx.joinClauses.join('\n');
    }
    if (whereClause) {
        sql += `\nWHERE ${whereClause}`;
    }
    if (groupByClause) {
        sql += `\nGROUP BY ${groupByClause}`;
    }
    if (havingClause) {
        sql += `\nHAVING ${havingClause}`;
    }
    if (orderByClause) {
        sql += `\nORDER BY ${orderByClause}`;
    }
    // 10. Build count query (never includes LIMIT — always counts total matching rows)
    let countSql = `SELECT COUNT(*) as total FROM ${entityDef.table} ${ctx.primaryTableAlias}`;
    if (ctx.joinClauses.length > 0) {
        countSql += '\n' + ctx.joinClauses.join('\n');
    }
    if (whereClause) {
        countSql += `\nWHERE ${whereClause}`;
    }
    // Now append LIMIT to the main query (after count SQL is built)
    if (config.limit && config.limit > 0) {
        sql += `\nLIMIT ?`;
        ctx.paramValues.push(config.limit);
    }
    const params = ctx.paramValues.slice(startIdx);
    logger_1.default.debug('Report query:', { sql, params });
    try {
        // Execute count query (uses same params as main query, minus any LIMIT param)
        const countParams = ctx.paramValues.slice(startIdx, config.limit ? params.length - 1 : params.length);
        const countResult = database_1.default.prepare(countSql).get(...countParams);
        const totalCount = countResult?.total ?? 0;
        // Execute main query
        const rows = database_1.default.prepare(sql).all(...params);
        // Build column names from SELECT items (aliases)
        const colNames = [];
        for (const item of selectItems) {
            const asMatch = item.match(/AS\s+(.+)$/i);
            if (asMatch) {
                colNames.push(asMatch[1].replace(/^"|"$/g, ''));
            }
            else {
                colNames.push(item.replace(/^e\./, '').replace(/^"|"$/g, ''));
            }
        }
        const elapsedMs = Date.now() - startTime;
        return {
            columns: colNames,
            rows,
            totalCount,
            elapsedMs,
        };
    }
    catch (error) {
        logger_1.default.error('Report query execution error:', { sql, error: error.message });
        throw new Error(`Query execution failed: ${error.message}`, { cause: error });
    }
}
// ── SELECT Builder ───────────────────────────────────────────
function buildSelectClause(config, entityDef, ctx) {
    const items = [];
    const isGrouped = config.groupBy?.enabled && config.groupBy.fields.length > 0;
    for (const col of config.columns) {
        if (!ctx.validFieldNames.has(col.field)) {
            throw new Error(`Column field "${col.field}" not found on entity "${config.entity}"`);
        }
        const isComputed = config.computedColumns?.some(cc => cc.name === col.field);
        const alias = quoteIdentifier(col.alias || col.field);
        if (isComputed) {
            const cc = config.computedColumns.find(c => c.name === col.field);
            items.push(`${cc.expression} AS ${alias}`);
        }
        else {
            items.push(`${ctx.primaryTableAlias}.${quoteIdentifier(col.field)} AS ${alias}`);
        }
    }
    // If grouped, also add group by fields that aren't already selected
    if (isGrouped) {
        for (const gf of config.groupBy.fields) {
            if (!config.columns.some(c => c.field === gf)) {
                items.push(`${ctx.primaryTableAlias}.${quoteIdentifier(gf)} AS ${quoteIdentifier(gf)}`);
            }
        }
    }
    // Add computed columns referenced in ORDER BY that aren't already in the SELECT
    if (config.computedColumns && config.sort) {
        const sortFieldNames = new Set(config.sort.map(s => s.field));
        for (const cc of config.computedColumns) {
            if (sortFieldNames.has(cc.name) && !config.columns.some(c => c.field === cc.name)) {
                items.push(`${cc.expression} AS ${quoteIdentifier(cc.name)}`);
            }
        }
    }
    return items;
}
// ── FROM/JOIN Builder ───────────────────────────────────────
function buildFromClause(entityDef, _ctx) {
    return `${entityDef.table} ${_ctx.primaryTableAlias}`;
}
function resolveNeededJoins(config, entityDef, ctx) {
    // Collect all field references from columns, filters, sorts, group by
    const referencedFields = new Set();
    for (const col of config.columns) {
        referencedFields.add(col.field);
    }
    if (config.filters) {
        collectFilterFields(config.filters, referencedFields);
    }
    if (config.sort) {
        for (const s of config.sort) {
            referencedFields.add(s.field);
        }
    }
    if (config.groupBy?.fields) {
        for (const f of config.groupBy.fields) {
            referencedFields.add(f);
        }
    }
    // Check which fields belong to joined entities
    for (const join of entityDef.joins) {
        const joinEntity = (0, entityRegistry_1.getEntity)(join.entity);
        if (!joinEntity)
            continue;
        const joinFieldNames = new Set(joinEntity.fields.map(f => f.name));
        let needsJoin = false;
        for (const field of referencedFields) {
            if (joinFieldNames.has(field)) {
                needsJoin = true;
                break;
            }
        }
        if (needsJoin) {
            const joinAlias = `j_${join.entity}`;
            ctx.usedJoins.set(join.entity, joinAlias);
            ctx.joinClauses.push(`LEFT JOIN ${joinEntity.table} ${joinAlias} ON ${ctx.primaryTableAlias}.${quoteIdentifier(join.localField)} = ${joinAlias}.${quoteIdentifier(join.foreignField)}`);
        }
    }
}
function collectFilterFields(filters, fields) {
    for (const f of filters) {
        if (f.field) {
            fields.add(f.field);
        }
        if (f.children && f.children.length > 0) {
            collectFilterFields(f.children, fields);
        }
    }
}
// ── WHERE Builder ────────────────────────────────────────────
function buildWhereClause(filters, ctx) {
    if (!filters || filters.length === 0)
        return '';
    const clauses = filters.map(f => buildFilterExpression(f, ctx, false));
    const nonEmpty = clauses.filter(c => c !== '');
    if (nonEmpty.length === 0)
        return '';
    return nonEmpty.join(' AND ');
}
/**
 * Build a single filter expression.
 *
 * @param useHavingMode - when true, don't alias with table prefix (for HAVING clauses
 *                        where filters reference aggregate aliases, not table columns)
 */
function buildFilterExpression(filter, ctx, useHavingMode = false) {
    // Handle logical operator groups (AND/OR)
    if (filter.logicalOperator && filter.children && filter.children.length > 0) {
        const children = filter.children.map(c => buildFilterExpression(c, ctx, useHavingMode));
        const nonEmpty = children.filter(c => c !== '');
        if (nonEmpty.length === 0)
            return '';
        if (nonEmpty.length === 1)
            return nonEmpty[0];
        return `(${nonEmpty.join(` ${filter.logicalOperator} `)})`;
    }
    if (!filter.field || !filter.operator)
        return '';
    // Validate field name (skip for HAVING mode — references aggregate aliases)
    if (!useHavingMode) {
        if (!ctx.validFieldNames.has(filter.field)) {
            throw new Error(`Filter field "${filter.field}" not found`);
        }
    }
    // For WHERE: use table-prefixed column. For HAVING: use bare field (aggregate alias)
    const col = useHavingMode
        ? quoteIdentifier(filter.field)
        : `${ctx.primaryTableAlias}.${quoteIdentifier(filter.field)}`;
    const value = filter.value;
    switch (filter.operator) {
        case 'equals': {
            if (value === null || value === undefined)
                return `${col} IS NULL`;
            const rd = checkRelativeDate(value);
            if (rd)
                return `${col} = ${rd.sqlExpr}`;
            ctx.paramValues.push(value);
            return `${col} = ?`;
        }
        case 'not_equals': {
            if (value === null || value === undefined)
                return `${col} IS NOT NULL`;
            const rd = checkRelativeDate(value);
            if (rd)
                return `${col} != ${rd.sqlExpr}`;
            ctx.paramValues.push(value);
            return `${col} != ?`;
        }
        case 'greater_than': {
            const rd = checkRelativeDate(value);
            if (rd)
                return `${col} > ${rd.sqlExpr}`;
            ctx.paramValues.push(value);
            return `${col} > ?`;
        }
        case 'less_than': {
            const rd = checkRelativeDate(value);
            if (rd)
                return `${col} < ${rd.sqlExpr}`;
            ctx.paramValues.push(value);
            return `${col} < ?`;
        }
        case 'greater_or_equal': {
            const rd = checkRelativeDate(value);
            if (rd)
                return `${col} >= ${rd.sqlExpr}`;
            ctx.paramValues.push(value);
            return `${col} >= ?`;
        }
        case 'less_or_equal': {
            const rd = checkRelativeDate(value);
            if (rd)
                return `${col} <= ${rd.sqlExpr}`;
            ctx.paramValues.push(value);
            return `${col} <= ?`;
        }
        case 'contains': {
            ctx.paramValues.push(`%${value}%`);
            return `${col} LIKE ?`;
        }
        case 'starts_with': {
            ctx.paramValues.push(`${value}%`);
            return `${col} LIKE ?`;
        }
        case 'ends_with': {
            ctx.paramValues.push(`%${value}`);
            return `${col} LIKE ?`;
        }
        case 'in_list': {
            if (!Array.isArray(value) || value.length === 0)
                return '1=0';
            const rd = checkRelativeDate(value[0]);
            if (rd) {
                // For date lists with relative dates, inline each
                const items = value.map((v) => {
                    const r = checkRelativeDate(v);
                    return r ? r.sqlExpr : '?';
                });
                const nonParam = value.filter((v, i) => !checkRelativeDate(v));
                ctx.paramValues.push(...nonParam);
                return `${col} IN (${items.join(', ')})`;
            }
            const placeholders = value.map(() => '?').join(', ');
            ctx.paramValues.push(...value);
            return `${col} IN (${placeholders})`;
        }
        case 'not_in': {
            if (!Array.isArray(value) || value.length === 0)
                return '';
            const placeholders = value.map(() => '?').join(', ');
            ctx.paramValues.push(...value);
            return `${col} NOT IN (${placeholders})`;
        }
        case 'between': {
            if (!Array.isArray(value) || value.length < 2)
                return '1=1';
            const rd1 = checkRelativeDate(value[0]);
            const rd2 = checkRelativeDate(value[1]);
            const expr1 = rd1 ? rd1.sqlExpr : '?';
            const expr2 = rd2 ? rd2.sqlExpr : '?';
            if (!rd1)
                ctx.paramValues.push(value[0]);
            if (!rd2)
                ctx.paramValues.push(value[1]);
            return `${col} BETWEEN ${expr1} AND ${expr2}`;
        }
        case 'is_null':
            return `${col} IS NULL`;
        case 'is_not_null':
            return `${col} IS NOT NULL`;
        default:
            return '';
    }
}
// ── GROUP BY Builder ────────────────────────────────────────
function buildGroupByClause(config, ctx) {
    if (!config.groupBy?.enabled || !config.groupBy.fields.length)
        return '';
    return config.groupBy.fields
        .map(f => {
        if (!ctx.validFieldNames.has(f)) {
            throw new Error(`Group by field "${f}" not found`);
        }
        return `${ctx.primaryTableAlias}.${quoteIdentifier(f)}`;
    })
        .join(', ');
}
// ── HAVING Builder ──────────────────────────────────────────
function buildHavingClause(config, ctx) {
    if (!config.groupBy?.having || config.groupBy.having.length === 0)
        return '';
    // HAVING filters use aggregate aliases (computed column names), not table columns.
    // So we use havingMode=true which skips table prefix and validFieldNames check.
    const havingMode = true;
    const clauses = config.groupBy.having.map(f => buildFilterExpression(f, ctx, havingMode));
    const nonEmpty = clauses.filter(c => c !== '');
    if (nonEmpty.length === 0)
        return '';
    return nonEmpty.join(' AND ');
}
// ── ORDER BY Builder ────────────────────────────────────────
function buildOrderByClause(sort, config, ctx) {
    if (!sort || sort.length === 0)
        return '';
    const computedNames = new Set((config.computedColumns || []).map(cc => cc.name));
    return sort
        .map(s => {
        if (!ctx.validFieldNames.has(s.field)) {
            throw new Error(`Sort field "${s.field}" not found`);
        }
        const dir = s.direction?.toLowerCase() === 'desc' ? 'DESC' : 'ASC';
        // Computed columns are aliases in SELECT — reference bare name without table prefix
        if (computedNames.has(s.field)) {
            return `${quoteIdentifier(s.field)} ${dir}`;
        }
        return `${ctx.primaryTableAlias}.${quoteIdentifier(s.field)} ${dir}`;
    })
        .join(', ');
}
exports.default = {
    executeReport,
};
//# sourceMappingURL=reportQueryEngine.js.map