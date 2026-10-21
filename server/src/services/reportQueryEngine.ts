/**
 * Report Query Engine
 * Translates a report config JSON into a SQL query and executes it.
 *
 * Accepts a config (same format stored in custom_reports.config) and
 * returns rows from the database with column names mapped to aliases.
 */

import db from '../config/database';
import { getEntity } from './entityRegistry';
import type { EntityDefinition } from './entityRegistry';
import logger from '../utils/logger';
import { validateConfigExpressions } from './expressionValidator';
import { errorMessage } from '../utils/errorMessage';
import { SqlParam } from '../utils/sqlTypes';

// ── Types ────────────────────────────────────────────────────

export interface ColumnDef {
  field: string;
  alias?: string;
  format?: string;
  width?: number;
  visible?: boolean;
}

export interface ComputedColumnDef {
  name: string;
  expression: string;
  type: string;
}

export interface FilterDef {
  field?: string;
  operator: FilterOperator;
  value?: SqlParam | SqlParam[];
  children?: FilterDef[];   // for AND/OR groups
  logicalOperator?: 'AND' | 'OR';
}

export type FilterOperator =
  | 'equals' | 'not_equals'
  | 'greater_than' | 'less_than'
  | 'greater_or_equal' | 'less_or_equal'
  | 'contains' | 'starts_with' | 'ends_with'
  | 'in_list' | 'not_in'
  | 'between'
  | 'is_null' | 'is_not_null';

export interface SortDef {
  field: string;
  direction: 'asc' | 'desc';
}

export interface GroupByDef {
  enabled: boolean;
  fields: string[];
  aggregates?: { field: string; fn: string; alias?: string }[];
  having?: FilterDef[];
}

export interface ReportConfig {
  entity: string;
  columns: ColumnDef[];
  computedColumns?: ComputedColumnDef[];
  filters?: FilterDef[];
  sort?: SortDef[];
  groupBy?: GroupByDef;
  limit?: number;
}

export interface QueryResult {
  columns: string[];          // Column names (aliases or field names)
  rows: Record<string, unknown>[]; // Result rows
  totalCount: number;
  elapsedMs: number;
}

// ── Relative Date Resolution ─────────────────────────────────

const RELATIVE_DATE_TOKENS: Record<string, string> = {
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
function resolveRelativeDate(value: string): string | null {
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
 * Narrow a filter value for the single-value operators.
 *
 * The scalar operators (equals, greater_than, ...) bind exactly one
 * placeholder, so neither an array nor a missing value has meaning here.
 * better-sqlite3 rejects both at bind time; catching them here turns an
 * opaque driver TypeError into a message that names the actual problem.
 */
function scalarParam(value: SqlParam | SqlParam[] | undefined): SqlParam {
  if (Array.isArray(value)) {
    throw new Error('Operator requires a single value, received an array');
  }
  if (value === undefined) {
    throw new Error('Operator requires a value, received none');
  }
  return value;
}

/**
 * Check if a value is a relative date expression that should be inlined as SQL.
 * Returns { sqlExpr } if it should be inlined, or null to treat as a parameter value.
 */
function checkRelativeDate(value: unknown): { sqlExpr: string } | null {
  if (typeof value === 'string') {
    const sqlExpr = resolveRelativeDate(value);
    if (sqlExpr !== null) {
      return { sqlExpr };
    }
  }
  return null;
}

// ── Identifier Utilities ────────────────────────────────────

function quoteIdentifier(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

// ── Whitelist hardening (REP-002) ────────────────────────────

/** Real column names of a table (registry-controlled name, never user input). */
function realColumns(table: string): Set<string> {
  const rows = db.prepare(`PRAGMA table_info("${table.replace(/"/g, '""')}")`).all() as Array<{ name: string }>;
  return new Set(rows.map(r => r.name));
}

/**
 * A computed column's name becomes a "valid field" for filters, sorting and
 * grouping. If it could shadow a real column that is NOT in the registry
 * (bank_iban, cnic_no, password_hash...), the field whitelist would be
 * bypassed and the column could be probed through filters. So computed names
 * must be plain identifiers that collide with no column of the entity's
 * table or of any table it can join to, and with no registry field.
 */
function assertComputedNamesAreSafe(config: ReportConfig, entityDef: EntityDefinition): void {
  if (!Array.isArray(config.computedColumns) || config.computedColumns.length === 0) return;
  const taken = new Set<string>(entityDef.fields.map(f => f.name));
  for (const c of realColumns(entityDef.table)) taken.add(c);
  for (const join of entityDef.joins) {
    const joined = getEntity(join.entity);
    if (!joined) continue;
    for (const c of realColumns(joined.table)) taken.add(c);
    for (const f of joined.fields) taken.add(f.name);
  }
  const seen = new Set<string>();
  for (const cc of config.computedColumns) {
    if (typeof cc.name !== 'string' || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(cc.name)) {
      throw new Error(`Computed column name "${String(cc.name)}" must be a plain identifier`);
    }
    if (taken.has(cc.name)) {
      throw new Error(`Computed column name "${cc.name}" collides with an existing column; choose another name`);
    }
    if (seen.has(cc.name)) {
      throw new Error(`Computed column name "${cc.name}" is defined twice`);
    }
    seen.add(cc.name);
  }
}

// ── SQL Builder ──────────────────────────────────────────────

interface BuildContext {
  validFieldNames: Set<string>;
  primaryTableAlias: string;
  usedJoins: Map<string, string>;  // entityKey -> alias
  joinClauses: string[];
  paramValues: SqlParam[];
}

/**
 * Build and execute a report query from a config.
 */
export function executeReport(config: ReportConfig): QueryResult {
  const startTime = Date.now();

  // 1. Validate entity
  const entityDef = getEntity(config.entity);
  if (!entityDef) {
    throw new Error(`Entity "${config.entity}" not found in registry`);
  }

  // REP-18 defense in depth: validate computed-column expressions against the
  // safe grammar BEFORE any SQL is built. Even if a controller misses this,
  // nothing unvalidated ever reaches query construction.
  const entityFieldNames = new Set(entityDef.fields.map(f => f.name));
  validateConfigExpressions(config, entityFieldNames);
  assertComputedNamesAreSafe(config, entityDef);

  const ctx: BuildContext = {
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

  // The grouped count is taken from this point: same SELECT aliases, WHERE,
  // GROUP BY and HAVING as the main query, but no ORDER BY / LIMIT.
  const sqlBeforeOrder = sql;

  if (orderByClause) {
    sql += `\nORDER BY ${orderByClause}`;
  }

  // 10. Build count query (never includes LIMIT — always counts total matching rows).
  // A grouped report returns one row per GROUP, so its count must be the number
  // of groups surviving HAVING; the HAVING parameters then belong to this query
  // too (REP-004).
  let countInner = `FROM ${entityDef.table} ${ctx.primaryTableAlias}`;
  if (ctx.joinClauses.length > 0) {
    countInner += '\n' + ctx.joinClauses.join('\n');
  }
  if (whereClause) {
    countInner += `\nWHERE ${whereClause}`;
  }
  let countSql: string;
  if (groupByClause) {
    countSql = `SELECT COUNT(*) as total FROM (${sqlBeforeOrder})`;
  } else {
    countSql = `SELECT COUNT(*) as total ${countInner}`;
  }

  // Now append LIMIT to the main query (after count SQL is built)
  sql += `\nLIMIT ?`;
  ctx.paramValues.push(effectiveRowLimit(config.limit));

  const params = ctx.paramValues.slice(startIdx);

  logger.debug('Report query:', { sql, params });

  try {
    // Execute count query (uses same params as main query, minus any LIMIT param)
    const countParams = ctx.paramValues.slice(startIdx, params.length - 1);
    const countResult = db.prepare(countSql).get(...countParams) as { total: number } | undefined;
    const totalCount = countResult?.total ?? 0;

    // Execute main query
    const rows = db.prepare(sql).all(...params) as Record<string, unknown>[];

    // Build column names from SELECT items (aliases)
    const colNames: string[] = [];
    for (const item of selectItems) {
      const asMatch = item.match(/AS\s+(.+)$/i);
      if (asMatch) {
        colNames.push(asMatch[1].replace(/^"|"$/g, ''));
      } else {
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
  } catch (error: unknown) {
    logger.error('Report query execution error:', { sql, error: errorMessage(error) });
    throw new Error(`Query execution failed: ${errorMessage(error)}`, { cause: error });
  }
}

// ── SELECT Builder ───────────────────────────────────────────

function buildSelectClause(
  config: ReportConfig,
  entityDef: EntityDefinition,
  ctx: BuildContext
): string[] {
  const items: string[] = [];
  const isGrouped = config.groupBy?.enabled && config.groupBy.fields.length > 0;

  for (const col of config.columns) {
    if (!ctx.validFieldNames.has(col.field)) {
      throw new Error(`Column field "${col.field}" not found on entity "${config.entity}"`);
    }

    const isComputed = config.computedColumns?.some(cc => cc.name === col.field);
    const alias = quoteIdentifier(col.alias || col.field);

    if (isComputed) {
      const cc = config.computedColumns!.find(c => c.name === col.field)!;
      items.push(`${cc.expression} AS ${alias}`);
    } else {
      items.push(`${ctx.primaryTableAlias}.${quoteIdentifier(col.field)} AS ${alias}`);
    }
  }

  // If grouped, also add group by fields that aren't already selected
  if (isGrouped) {
    for (const gf of config.groupBy!.fields) {
      if (!config.columns.some(c => c.field === gf)) {
        items.push(`${ctx.primaryTableAlias}.${quoteIdentifier(gf)} AS ${quoteIdentifier(gf)}`);
      }
    }
  }

  // REP-005: `groupBy.aggregates` was validated but never rendered, so a grouped
  // report returned SQLite's arbitrary bare-column value per group. Emit them here.
  if (isGrouped) {
    items.push(...buildAggregateItems(config.groupBy!, entityDef, ctx));
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

/**
 * REP-005: LIKE wildcards are metacharacters, so a user's literal `%` or `_`
 * matched everything or any single character instead of the text they typed.
 * Escape them and declare the escape character on every generated LIKE.
 */
function escapeLikeWildcards(value: string): string {
  return value.replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

/** REP-005: a report may never ask for an unbounded number of rows. */
export const MAX_REPORT_ROWS = 1000;
export const DEFAULT_REPORT_ROWS = 500;

function effectiveRowLimit(requested: number | undefined): number {
  if (requested === undefined || !Number.isFinite(requested)) return DEFAULT_REPORT_ROWS;
  const whole = Math.floor(requested);
  if (whole <= 0) return DEFAULT_REPORT_ROWS;
  return Math.min(whole, MAX_REPORT_ROWS);
}

/**
 * REP-005: render `groupBy.aggregates` as SELECT items. Each aggregate is
 * restricted to a field the entity advertises, to an aggregate function the
 * registry lists for that field, and to a non-colliding alias.
 */
function buildAggregateItems(
  groupBy: GroupByDef,
  entityDef: EntityDefinition,
  ctx: BuildContext
): string[] {
  const items: string[] = [];
  const used = new Set(ctx.validFieldNames);

  for (const aggregate of groupBy.aggregates ?? []) {
    if (!ctx.validFieldNames.has(aggregate.field)) {
      throw new Error(`Aggregate field "${aggregate.field}" not found on entity "${entityDef.key}"`);
    }
    const fieldDef = entityDef.fields.find((f) => f.name === aggregate.field);
    const allowed = fieldDef?.aggregateFns ?? [];
    const fn = aggregate.fn.toUpperCase();
    if (!allowed.includes(fn as (typeof allowed)[number])) {
      throw new Error(
        `Aggregate function "${aggregate.fn}" is not available for field "${aggregate.field}"`
      );
    }

    const rawAlias = aggregate.alias || `${fn.toLowerCase()}_${aggregate.field}`;
    if (used.has(rawAlias)) {
      throw new Error(`Aggregate alias "${rawAlias}" collides with an existing column`);
    }
    used.add(rawAlias);
    ctx.validFieldNames.add(rawAlias);

    items.push(`${fn}(${ctx.primaryTableAlias}.${quoteIdentifier(aggregate.field)}) AS ${quoteIdentifier(rawAlias)}`);
  }

  return items;
}

// ── FROM/JOIN Builder ───────────────────────────────────────

function buildFromClause(entityDef: EntityDefinition, _ctx: BuildContext): string {
  return `${entityDef.table} ${_ctx.primaryTableAlias}`;
}

function resolveNeededJoins(
  config: ReportConfig,
  entityDef: EntityDefinition,
  ctx: BuildContext
): void {
  // Collect all field references from columns, filters, sorts, group by
  const referencedFields = new Set<string>();

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
    const joinEntity = getEntity(join.entity);
    if (!joinEntity) continue;

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

      ctx.joinClauses.push(
        `LEFT JOIN ${joinEntity.table} ${joinAlias} ON ${ctx.primaryTableAlias}.${quoteIdentifier(join.localField)} = ${joinAlias}.${quoteIdentifier(join.foreignField)}`
      );
    }
  }
}

function collectFilterFields(filters: FilterDef[], fields: Set<string>): void {
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

function buildWhereClause(
  filters: FilterDef[] | undefined,
  ctx: BuildContext
): string {
  if (!filters || filters.length === 0) return '';

  const clauses = filters.map(f => buildFilterExpression(f, ctx, false));
  const nonEmpty = clauses.filter(c => c !== '');
  if (nonEmpty.length === 0) return '';

  return nonEmpty.join(' AND ');
}

type FilterValue = SqlParam | SqlParam[] | undefined;
type FilterBuilder = (col: string, value: FilterValue, ctx: BuildContext) => string;

function buildEquality(
  col: string,
  value: FilterValue,
  ctx: BuildContext,
  negate: boolean
): string {
  if (value === null || value === undefined) return `${col} IS ${negate ? 'NOT ' : ''}NULL`;
  const rd = checkRelativeDate(value);
  if (rd) return `${col} ${negate ? '!=' : '='} ${rd.sqlExpr}`;
  ctx.paramValues.push(scalarParam(value));
  return `${col} ${negate ? '!=' : '='} ?`;
}

function buildComparison(
  col: string,
  sqlOperator: string,
  value: FilterValue,
  ctx: BuildContext
): string {
  const rd = checkRelativeDate(value);
  if (rd) return `${col} ${sqlOperator} ${rd.sqlExpr}`;
  ctx.paramValues.push(scalarParam(value));
  return `${col} ${sqlOperator} ?`;
}

function buildLike(
  col: string,
  value: FilterValue,
  ctx: BuildContext,
  pattern: 'contains' | 'starts_with' | 'ends_with'
): string {
  const escaped = escapeLikeWildcards(String(value));
  const wildcard =
    pattern === 'contains' ? `%${escaped}%`
    : pattern === 'starts_with' ? `${escaped}%`
    : `%${escaped}`;
  ctx.paramValues.push(wildcard);
  return `${col} LIKE ? ESCAPE '\\'`;
}

function buildInList(col: string, value: FilterValue, ctx: BuildContext): string {
  if (!Array.isArray(value) || value.length === 0) return '1=0';
  if (checkRelativeDate(value[0])) {
    const items = value.map((v) => {
      const r = checkRelativeDate(v);
      return r ? r.sqlExpr : '?';
    });
    ctx.paramValues.push(...value.filter((v) => !checkRelativeDate(v)));
    return `${col} IN (${items.join(', ')})`;
  }
  ctx.paramValues.push(...value);
  return `${col} IN (${value.map(() => '?').join(', ')})`;
}

function buildNotIn(col: string, value: FilterValue, ctx: BuildContext): string {
  if (!Array.isArray(value) || value.length === 0) return '';
  ctx.paramValues.push(...value);
  return `${col} NOT IN (${value.map(() => '?').join(', ')})`;
}

function buildBetween(col: string, value: FilterValue, ctx: BuildContext): string {
  if (!Array.isArray(value) || value.length < 2) return '1=1';
  const relativeStart = checkRelativeDate(value[0]);
  const relativeEnd = checkRelativeDate(value[1]);
  if (!relativeStart) ctx.paramValues.push(value[0]);
  if (!relativeEnd) ctx.paramValues.push(value[1]);
  const start = relativeStart ? relativeStart.sqlExpr : '?';
  const end = relativeEnd ? relativeEnd.sqlExpr : '?';
  return `${col} BETWEEN ${start} AND ${end}`;
}

const FILTER_BUILDERS: Record<FilterOperator, FilterBuilder> = {
  equals: (col, value, ctx) => buildEquality(col, value, ctx, false),
  not_equals: (col, value, ctx) => buildEquality(col, value, ctx, true),
  greater_than: (col, value, ctx) => buildComparison(col, '>', value, ctx),
  less_than: (col, value, ctx) => buildComparison(col, '<', value, ctx),
  greater_or_equal: (col, value, ctx) => buildComparison(col, '>=', value, ctx),
  less_or_equal: (col, value, ctx) => buildComparison(col, '<=', value, ctx),
  contains: (col, value, ctx) => buildLike(col, value, ctx, 'contains'),
  starts_with: (col, value, ctx) => buildLike(col, value, ctx, 'starts_with'),
  ends_with: (col, value, ctx) => buildLike(col, value, ctx, 'ends_with'),
  in_list: buildInList,
  not_in: buildNotIn,
  between: buildBetween,
  is_null: (col) => `${col} IS NULL`,
  is_not_null: (col) => `${col} IS NOT NULL`,
};

/**
 * Build a single filter expression.
 *
 * @param useHavingMode - when true, don't alias with table prefix (for HAVING clauses
 *                        where filters reference aggregate aliases, not table columns)
 */
function buildFilterExpression(
  filter: FilterDef,
  ctx: BuildContext,
  useHavingMode: boolean = false
): string {
  // Handle logical operator groups (AND/OR)
  if (filter.logicalOperator && filter.children && filter.children.length > 0) {
    const children = filter.children.map(c => buildFilterExpression(c, ctx, useHavingMode));
    const nonEmpty = children.filter(c => c !== '');
    if (nonEmpty.length === 0) return '';
    if (nonEmpty.length === 1) return nonEmpty[0];
    return `(${nonEmpty.join(` ${filter.logicalOperator} `)})`;
  }

  if (!filter.field || !filter.operator) return '';

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

  // `filter.operator` comes from a persisted report definition, so an
  // unrecognised value is possible at runtime even though the type forbids it.
  const build = FILTER_BUILDERS[filter.operator as FilterOperator];
  return typeof build === 'function' ? build(col, filter.value, ctx) : '';
}

// ── GROUP BY Builder ────────────────────────────────────────

function buildGroupByClause(config: ReportConfig, ctx: BuildContext): string {
  if (!config.groupBy?.enabled || !config.groupBy.fields.length) return '';

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

function buildHavingClause(config: ReportConfig, ctx: BuildContext): string {
  if (!config.groupBy?.enabled || !config.groupBy.fields.length) return '';
  if (!config.groupBy.having || config.groupBy.having.length === 0) return '';

  // HAVING filters use aggregate aliases (computed column names), not table columns,
  // so they are rendered without the table prefix. They are still validated against
  // the same whitelist (REP-002): an unvalidated quoted identifier here could name
  // any column of the table, including ones the registry deliberately hides.
  const havingMode = true;
  const havingFields = new Set<string>(ctx.validFieldNames);
  for (const a of config.groupBy.aggregates ?? []) {
    if (a.alias) havingFields.add(a.alias);
  }
  const checkHavingFields = (filters: FilterDef[]): void => {
    for (const f of filters) {
      if (f.field && !havingFields.has(f.field)) {
        throw new Error(`Having field "${f.field}" not found`);
      }
      if (f.children && f.children.length > 0) checkHavingFields(f.children);
    }
  };
  checkHavingFields(config.groupBy.having);
  const clauses = config.groupBy.having.map(f => buildFilterExpression(f, ctx, havingMode));
  const nonEmpty = clauses.filter(c => c !== '');
  if (nonEmpty.length === 0) return '';
  return nonEmpty.join(' AND ');
}

// ── ORDER BY Builder ────────────────────────────────────────

function buildOrderByClause(
  sort: SortDef[] | undefined,
  config: ReportConfig,
  ctx: BuildContext
): string {
  if (!sort || sort.length === 0) return '';

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

export default {
  executeReport,
};
