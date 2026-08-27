// ============================================================
// Global Search — Type Definitions
// ============================================================

/** A single search result (entity or page). */
export interface SearchResult {
  type: string;          // 'customer' | 'supplier' | 'product' | ... | 'page'
  id: number | string;   // numeric DB id for entities, string key for pages
  title: string;         // primary display text
  subtitle: string;      // secondary display text
  metadata: Record<string, unknown>;  // entity-specific extra fields
  actions: SearchAction[];
}

/** One actionable button for a search result. */
export interface SearchAction {
  id: string;            // e.g. 'open', 'create_invoice', 'print'
  label: string;         // e.g. 'Open Customer', 'Create Sales Invoice'
}

/** Top-level response from GET /api/search. */
export interface SearchResponse {
  query: string;
  results: SearchResult[];
  total: number;         // total results count across all entities
}

/** A static page/action registry entry. */
export interface PageAction {
  id: string;
  title: string;
  path: string;
  icon: string;          // Material icon name
  keywords?: string[];
  action?: boolean;      // true if this is an action (vs navigation page)
  /** Permissions required to see this page/action. */
  permission?: string;
}

/** Definition of an entity action (used in ENTITY_ACTIONS registry). */
export interface ActionDef {
  id: string;
  label: string;
  /** Required permission module:action, e.g. 'invoices:create'. */
  permission?: string;
  /** Optional status-based gate; row data is passed in. */
  condition?: (row: Record<string, unknown>) => boolean;
}

/** Raw row from an entity search query (before transformation). */
export interface EntityRow extends Record<string, unknown> {
  id: number;
}
